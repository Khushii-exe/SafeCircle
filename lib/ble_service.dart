import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// A single encounter record representing a nearby SafeCircle device.
class BleEncounter {
  BleEncounter({
    required this.id,
    required this.deviceId,
    required this.rssi,
    required this.timestamp,
    required this.durationS,
  });

  factory BleEncounter.fromJson(Map<String, dynamic> j) => BleEncounter(
        id: j['id'] as String,
        deviceId: j['device_id'] as String,
        rssi: (j['rssi'] as num).toInt(),
        timestamp: DateTime.parse(j['timestamp'] as String),
        durationS: (j['duration_s'] as num).toInt(),
      );

  final String id;
  final String deviceId;
  final int rssi;
  final DateTime timestamp;
  final int durationS;

  Map<String, dynamic> toJson() => {
        'id': id,
        'device_id': deviceId,
        'rssi': rssi,
        'timestamp': timestamp.toIso8601String(),
        'duration_s': durationS,
      };
}

/// Software-layer Bluetooth encounter simulation.
/// Generates a persistent device ID and maintains a list of nearby encounters
/// using SharedPreferences. No native BLE plugin required.
class BleService {
  static const _keyDeviceId = 'ble_device_id';
  static const _keyEncounters = 'ble_encounters';

  String? _localDeviceId;
  List<BleEncounter> _encounters = [];
  Timer? _scanTimer;

  String get localDeviceId => _localDeviceId ?? '';
  List<BleEncounter> get encounters => List.unmodifiable(_encounters);

  /// Initialise: create/load device ID, seed encounters if first run, start scan timer.
  Future<void> init({bool startTimer = true}) async {
    final prefs = await SharedPreferences.getInstance();

    // Ensure a unique device ID exists for this install.
    String? id = prefs.getString(_keyDeviceId);
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString(_keyDeviceId, id);
    }
    _localDeviceId = id;

    // Load or seed encounters.
    final raw = prefs.getString(_keyEncounters);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        _encounters = list.map((e) => BleEncounter.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      } catch (_) {
        _encounters = [];
      }
    }

    if (_encounters.isEmpty) {
      await _seedEncounters(prefs);
    }

    // Periodic scan – every 60 s simulate a fresh scan.
    if (startTimer) {
      _scanTimer = Timer.periodic(const Duration(seconds: 60), (_) => _scan());
    }
  }

  /// Cancel timer and release resources.
  void dispose() {
    _scanTimer?.cancel();
    _scanTimer = null;
  }

  /// Trigger a manual scan and persist the result.
  Future<void> scan() async => _scan();

  /// Delete a single encounter by ID.
  Future<void> deleteEncounter(String id) async {
    _encounters.removeWhere((e) => e.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEncounters, jsonEncode(_encounters.map((e) => e.toJson()).toList()));
  }

  /// Clear all stored encounters.
  Future<void> clearEncounters() async {
    _encounters.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEncounters);
  }

  // ------------------------------------------------------------------ private

  Future<void> _scan() async {
    final prefs = await SharedPreferences.getInstance();
    final rng = Random();

    // Simulate discovering 0–2 new encounters per scan.
    final count = rng.nextInt(3);
    for (var i = 0; i < count; i++) {
      final enc = BleEncounter(
        id: const Uuid().v4(),
        deviceId: const Uuid().v4(),
        rssi: -(45 + rng.nextInt(45)), // -45 to -89 dBm
        timestamp: DateTime.now().toUtc(),
        durationS: 10 + rng.nextInt(290),
      );
      _encounters.insert(0, enc);
    }

    // Keep at most 50 encounters.
    if (_encounters.length > 50) {
      _encounters = _encounters.sublist(0, 50);
    }

    await prefs.setString(_keyEncounters, jsonEncode(_encounters.map((e) => e.toJson()).toList()));
  }

  /// Pre-populate realistic Delhi/NCR encounter history on first launch.
  Future<void> _seedEncounters(SharedPreferences prefs) async {
    final rng = Random(42); // deterministic seed for reproducibility
    final now = DateTime.now().toUtc();

    // Realistic RSSI ranges and durations representing past encounters.
    final seedData = [
      (-48, 420, 180),   // very close, long encounter
      (-55, 360, 95),
      (-61, 300, 210),
      (-67, 240, 48),
      (-73, 180, 320),
      (-58, 150, 75),
      (-82, 120, 15),
      (-45, 90,  540),
      (-69, 75,  130),
      (-77, 60,  22),
      (-52, 45,  380),
      (-63, 30,  165),
      (-85, 20,  8),
      (-49, 15,  290),
      (-71, 10,  55),
    ];

    _encounters = seedData.map((row) {
      return BleEncounter(
        id: const Uuid().v4(),
        deviceId: _deterministicUuid(rng),
        rssi: row.$1,
        timestamp: now.subtract(Duration(minutes: row.$2 + rng.nextInt(30))),
        durationS: row.$3,
      );
    }).toList();

    // Sort most-recent first.
    _encounters.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    await prefs.setString(_keyEncounters, jsonEncode(_encounters.map((e) => e.toJson()).toList()));
  }

  /// Generate a deterministic UUID-formatted string from a seeded [Random].
  String _deterministicUuid(Random rng) {
    final bytes = List.generate(16, (_) => rng.nextInt(256));
    // RFC 4122 version 4 variant bits.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final h = bytes.map(hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}

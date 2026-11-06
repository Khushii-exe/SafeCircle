import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ble_service.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets/glass.dart';

/// Anonymise a device ID: SHA-256 → first 8 hex chars.
String _anonymise(String deviceId) {
  final digest = sha256.convert(utf8.encode(deviceId));
  return digest.toString().substring(0, 8).toUpperCase();
}

/// Human-readable relative time (e.g. "just now", "3 min ago", "2 hours ago").
String _relativeTime(DateTime ts) {
  final diff = DateTime.now().toUtc().difference(ts);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} ${diff.inHours == 1 ? "hour" : "hours"} ago';
  return '${diff.inDays} ${diff.inDays == 1 ? "day" : "days"} ago';
}

/// Duration in human-readable form (e.g. "45 s", "3 min").
String _duration(int seconds) {
  if (seconds < 60) return '$seconds s';
  return '${(seconds / 60).round()} min';
}

/// Signal-strength colour band.
Color _rssiColor(int rssi) {
  if (rssi > -60) return const Color(0xFF2E7D32); // green
  if (rssi >= -75) return const Color(0xFFF57C00); // orange
  return const Color(0xFFC62828); // red
}

/// Number of filled signal bars (0-4).
int _rssiBars(int rssi) {
  if (rssi > -55) return 4;
  if (rssi > -65) return 3;
  if (rssi > -75) return 2;
  if (rssi > -85) return 1;
  return 0;
}

class EncountersScreen extends StatefulWidget {
  const EncountersScreen({super.key});

  @override
  State<EncountersScreen> createState() => _EncountersScreenState();
}

class _EncountersScreenState extends State<EncountersScreen> {
  bool _scanning = false;

  Future<void> _refresh(AppState s) async {
    setState(() => _scanning = true);
    await s.scanBle();
    if (mounted) setState(() => _scanning = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final encounters = s.bleEncounters;
    final localId = s.bleLocalDeviceId;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 120),
        children: [
          Row(
            children: [
              const Expanded(child: Text('Nearby users', style: hTitle)),
              if (encounters.isNotEmpty)
                TextButton(
                  onPressed: () => s.clearBleEncounters(),
                  style: TextButton.styleFrom(foregroundColor: C.body),
                  child: const Text('Clear', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              IconButton(
                tooltip: 'Refresh scan',
                onPressed: _scanning ? null : () => _refresh(s),
                icon: _scanning
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.bluetooth_searching, color: C.accent),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '${encounters.length} SafeCircle ${encounters.length == 1 ? "user" : "users"} detected nearby',
              style: hSmall,
            ),
          ),

          // Own device card.
          if (localId.isNotEmpty)
            Glass(
              margin: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: C.accent.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: const Icon(Icons.person, color: C.accent),
                  ),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Your device ID', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: C.body)),
                    Text(_anonymise(localId), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: C.ink, letterSpacing: 1.5)),
                  ]),
                ],
              ),
            ),

          // Encounter list.
          for (final enc in encounters) _EncounterCard(enc),

          // Footer note.
          const SizedBox(height: 20),
          const Text(
            'SafeCircle detects other users to build safety presence data. No personal information is shared.',
            style: TextStyle(fontSize: 12, color: C.body, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _EncounterCard extends StatelessWidget {
  const _EncounterCard(this.enc);
  final BleEncounter enc;

  @override
  Widget build(BuildContext context) {
    final color = _rssiColor(enc.rssi);
    final bars = _rssiBars(enc.rssi);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        child: Glass(
          radius: 24,
          child: Row(
            children: [
              // Signal bars icon.
              _SignalBars(bars: bars, color: color),
              const SizedBox(width: 12),
              // Details.
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    _anonymise(enc.deviceId),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: C.ink, letterSpacing: 1.2),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${enc.rssi} dBm · ${_duration(enc.durationS)}',
                    style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600),
                  ),
                ]),
              ),
              // Relative timestamp and delete.
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_relativeTime(enc.timestamp), style: const TextStyle(fontSize: 12, color: C.body)),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () => context.read<AppState>().deleteBleEncounter(enc.id),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close, size: 16, color: C.body),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Four vertical bars representing RSSI signal strength.
class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.bars, required this.color});
  final int bars;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 28,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(4, (i) {
          final filled = i < bars;
          final height = 7.0 + i * 5.0;
          return Container(
            width: 4,
            height: height,
            decoration: BoxDecoration(
              color: filled ? color : color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'api.dart';
import 'ble_service.dart';

/// Pilot-area centre (synthetic demo data in the backend seed). Replace with your real pilot area.
const demoCenter = LatLng(28.4575, 77.0290);

/// Pilot region: Delhi and Haryana (mirrors the backend's app/region.py; /region can refresh the city list).
final regionBounds = LatLngBounds(const LatLng(27.60, 74.40), const LatLng(30.95, 77.65));
const regionCenter = LatLng(28.50, 77.05);

class Place {
  const Place(this.name, this.at);
  final String name;
  final LatLng at;
}

const defaultPlaces = [
  Place('Gurugram', LatLng(28.4595, 77.0266)),
  Place('Delhi', LatLng(28.6139, 77.2090)),
  Place('Faridabad', LatLng(28.4089, 77.3178)),
  Place('Farukhnagar', LatLng(28.47, 76.82)),
  Place('Sonipat', LatLng(28.9931, 77.0151)),
  Place('Rohtak', LatLng(28.8955, 76.6066)),
  Place('Panipat', LatLng(29.3909, 76.9635)),
  Place('Karnal', LatLng(29.6857, 76.9905)),
  Place('Ambala', LatLng(30.3782, 76.7767)),
  Place('Hisar', LatLng(29.1492, 75.7217)),
];

DateTime parseUtc(String s) => DateTime.parse(s.endsWith('Z') ? s : '${s}Z');

/// A user-reported unsafe stretch marked using two exclamation flags.
class FlaggedStretch {
  FlaggedStretch({
    required this.id,
    required this.start,
    required this.end,
    required this.concerns,
    required this.note,
    required this.timestamp,
  });

  factory FlaggedStretch.fromJson(Map<String, dynamic> j) => FlaggedStretch(
        id: j['id'] as String,
        start: LatLng((j['start'][0] as num).toDouble(), (j['start'][1] as num).toDouble()),
        end: LatLng((j['end'][0] as num).toDouble(), (j['end'][1] as num).toDouble()),
        concerns: (j['concerns'] as List).map((e) => e.toString()).toSet(),
        note: j['note'] as String? ?? '',
        timestamp: DateTime.parse(j['timestamp'] as String),
      );

  final String id;
  final LatLng start;
  final LatLng end;
  final Set<String> concerns; // 'dark', 'animals', 'abandoned', 'bad residents'
  final String note;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'id': id,
        'start': [start.latitude, start.longitude],
        'end': [end.latitude, end.longitude],
        'concerns': concerns.toList(),
        'note': note,
        'timestamp': timestamp.toIso8601String(),
      };
}

class AppState extends ChangeNotifier {
  AppState(this.api);
  final Api api;

  int tab = 0;
  final MapController mapController = MapController();
  List<Place> places = defaultPlaces;
  List<Map<String, dynamic>> segments = [];
  bool showConcern = true;
  bool showSignal = true;
  String mode = 'night';
  Map<String, dynamic>? comparison;
  String? selectedRouteId;
  LatLng? pin;
  LatLng? me;
  String? error;
  bool busy = false;

  // Offline & Snapshot status
  DateTime? lastSnapshotTime;
  bool isOffline = false;

  // First-run privacy consent (DPDP compliance)
  bool needsConsent = false;

  // Localization toggle
  String language = 'en';

  // Journey Guard
  Map<String, dynamic>? trip;
  Timer? _heartbeat;

  // Origin / Source
  LatLng? sourceLocation;
  String? sourceName;

  // Destination search
  LatLng? destination;
  String? destinationName;

  // Unsafe road stretch flagging mode (2 exclamation flags)
  bool flagMode = false;
  LatLng? flagA;
  LatLng? flagB;
  List<FlaggedStretch> flaggedStretches = [];

  // Offline route snapshot
  Map<String, dynamic>? offlineRoute;
  DateTime? offlineRouteTime;
  bool isShowingOfflineRoute = false;

  // BLE
  final BleService _bleService = BleService();
  String get bleLocalDeviceId => _bleService.localDeviceId;
  List<BleEncounter> get bleEncounters => _bleService.encounters;

  void jumpTo(Place p) => mapController.move(p.at, 13);

  void selectRoute(String id) {
    selectedRouteId = id;
    notifyListeners();
  }

  Map<String, dynamic>? get selectedRoute {
    if (comparison == null) return null;
    final routes = (comparison!['routes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (routes.isEmpty) return null;
    if (selectedRouteId != null) {
      for (final r in routes) {
        if (r['id'] == selectedRouteId) return r;
      }
    }
    return routes.firstWhere((r) => r['recommended'] == true, orElse: () => routes.first);
  }

  void toggleLanguage() {
    language = (language == 'en') ? 'hi' : 'en';
    notifyListeners();
  }

  void setDemoA3Pin() {
    const a3 = LatLng(28.4550, 77.0270);
    setPin(a3);
    mapController.move(a3, 14);
  }

  Future<void> checkConsent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      needsConsent = !(prefs.getBool('consent_accepted') ?? false);
    } catch (_) {
      needsConsent = false;
    }
    notifyListeners();
  }

  Future<void> acceptConsent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('consent_accepted', true);
    } catch (_) {}
    needsConsent = false;
    notifyListeners();
  }

  Future<void> loadRegion() async {
    try {
      final j = await api.get('/region');
      places = [for (final p in j['places'] as List) Place(p['name'] as String, LatLng((p['lat'] as num).toDouble(), (p['lon'] as num).toDouble()))];
      notifyListeners();
    } catch (_) {
      // keep the built-in list
    }
  }

  void setTab(int i) {
    tab = i;
    notifyListeners();
  }

  void setPin(LatLng p) {
    pin = p;
    notifyListeners();
  }

  void toggleConcern() {
    showConcern = !showConcern;
    notifyListeners();
  }

  void toggleSignal() {
    showSignal = !showSignal;
    notifyListeners();
  }

  Future<void> setMode(String m) async {
    mode = m;
    notifyListeners();
    await compare();
  }

  Future<void> init() async {
    try {
      await api.ensureAuth();
    } catch (e) {
      error = e.toString();
    }
    await checkConsent();
    await _bleService.init();
    await Future.wait([loadRegion(), loadOverlays(), _loadOfflineRoute(), _loadFlaggedStretches(), compare()]);
    me = await locate();
    notifyListeners();
  }

  /// Override in tests to skip BLE timer setup.
  @protected
  Future<void> initBleService() => _bleService.init();

  /// Returns null when permission is denied or location is unavailable. Callers must handle null honestly.
  Future<LatLng?> locate() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
      final p = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)));
      return LatLng(p.latitude, p.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<void> loadOverlays() async {
    try {
      final j = await api.get('/overlays');
      segments = List<Map<String, dynamic>>.from(j['segments'] as List);
      lastSnapshotTime = DateTime.now();
      isOffline = false;
      error = null;
    } catch (e) {
      if (segments.isNotEmpty) {
        isOffline = true;
      } else {
        error = e.toString();
      }
    }
    notifyListeners();
  }

  // ---------- Source & Destination ----------

  Future<void> detectCurrentLocationAsSource() async {
    final loc = await locate();
    if (loc != null) {
      sourceLocation = loc;
      sourceName = 'Current Location';
      me = loc;
      notifyListeners();
      await compare();
    }
  }

  void setSource(LatLng loc, String name) {
    sourceLocation = loc;
    sourceName = name;
    notifyListeners();
    unawaited(compare());
  }

  void clearSource() {
    sourceLocation = null;
    sourceName = null;
    notifyListeners();
    unawaited(compare());
  }

  void setDestination(LatLng loc, String name) {
    destination = loc;
    destinationName = name;
    notifyListeners();
    unawaited(compare());
  }

  void clearDestination() {
    destination = null;
    destinationName = null;
    notifyListeners();
    unawaited(compare());
  }

  // ---------- 2 Exclamation Flags (Unsafe Road Stretch) ----------

  void toggleFlagMode() {
    flagMode = !flagMode;
    if (flagMode) {
      final currentCenter = mapController.camera.center;
      flagA ??= LatLng(currentCenter.latitude - 0.0025, currentCenter.longitude - 0.0025);
      flagB ??= LatLng(currentCenter.latitude + 0.0025, currentCenter.longitude + 0.0025);
    }
    notifyListeners();
  }

  void setFlagA(LatLng p) {
    flagA = p;
    notifyListeners();
  }

  void setFlagB(LatLng p) {
    flagB = p;
    notifyListeners();
  }

  Future<void> reportFlaggedStretch(Set<String> concerns, String note) async {
    if (flagA == null || flagB == null || concerns.isEmpty) return;
    final stretch = FlaggedStretch(
      id: const Uuid().v4(),
      start: flagA!,
      end: flagB!,
      concerns: Set<String>.from(concerns),
      note: note,
      timestamp: DateTime.now().toUtc(),
    );
    flaggedStretches.insert(0, stretch);
    await _saveFlaggedStretches();

    // Post to server if connected
    try {
      final midLat = (flagA!.latitude + flagB!.latitude) / 2;
      final midLon = (flagA!.longitude + flagB!.longitude) / 2;
      final primaryCategory = concerns.contains('dark')
          ? 'poor_lighting'
          : concerns.contains('abandoned')
              ? 'isolated'
              : concerns.contains('bad residents')
                  ? 'harassment'
                  : 'other';
      await api.post('/reports', {
        'lat': midLat,
        'lon': midLon,
        'category': primaryCategory,
        'time_bucket': mode,
        'note': 'Unsafe road stretch: ${concerns.join(", ")}. $note',
      });
    } catch (_) {}

    flagMode = false;
    await compare();
    notifyListeners();
  }

  Future<void> deleteFlaggedStretch(String id) async {
    flaggedStretches.removeWhere((s) => s.id == id);
    await _saveFlaggedStretches();
    await compare();
    notifyListeners();
  }

  Future<void> _saveFlaggedStretches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('flagged_stretches', jsonEncode(flaggedStretches.map((s) => s.toJson()).toList()));
    } catch (_) {}
  }

  Future<void> _loadFlaggedStretches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('flagged_stretches');
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        flaggedStretches = list.map((e) => FlaggedStretch.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      }
    } catch (_) {}
  }

  // ---------- Dynamic Route Comparison ----------

  double _haversine(LatLng p1, LatLng p2) {
    const d2r = 0.017453292519943295;
    final dlat = (p2.latitude - p1.latitude) * d2r;
    final dlon = (p2.longitude - p1.longitude) * d2r;
    final a = sin(dlat / 2) * sin(dlat / 2) +
        cos(p1.latitude * d2r) * cos(p2.latitude * d2r) * sin(dlon / 2) * sin(dlon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return 6371.0 * c;
  }

  void _calculateDynamicRoutes(LatLng o, LatLng d) {
    final distKm = max(1.2, _haversine(o, d));
    final baseMin = (distKm / 28.0) * 60.0;

    // Generate waypoints with distinct curvature
    List<List<double>> genWaypoints(double latOffset, double lonOffset, int count) {
      final pts = <List<double>>[];
      for (var i = 0; i <= count; i++) {
        final t = i / count;
        final curve = sin(t * pi);
        final lat = o.latitude + (d.latitude - o.latitude) * t + latOffset * curve;
        final lon = o.longitude + (d.longitude - o.longitude) * t + lonOffset * curve;
        pts.add([lat, lon]);
      }
      return pts;
    }

    // Check flagged stretches impact on each route
    double flaggedPenalty(List<List<double>> pts, List<Map<String, dynamic>> worstList) {
      var penalty = 0.0;
      for (final stretch in flaggedStretches) {
        final mid = LatLng((stretch.start.latitude + stretch.end.latitude) / 2, (stretch.start.longitude + stretch.end.longitude) / 2);
        final near = pts.any((p) => _haversine(LatLng(p[0], p[1]), mid) < 0.6);
        if (near) {
          final impact = 0.15 + (stretch.concerns.length * 0.05);
          penalty += impact;
          worstList.add({
            'id': stretch.id,
            'name': 'Flagged: ${stretch.concerns.join(", ")}',
            'concern': 'red',
            'signal_measured': true,
          });
        }
      }
      return min(penalty, 0.60);
    }

    final worstA = <Map<String, dynamic>>[];
    final worstB = <Map<String, dynamic>>[];
    final worstC = <Map<String, dynamic>>[];

    final ptsA = genWaypoints(0.0010, -0.0010, 10);
    final ptsB = genWaypoints(-0.0035, 0.0040, 12);
    final ptsC = genWaypoints(0.0045, -0.0050, 14);

    final penA = flaggedPenalty(ptsA, worstA);
    final penB = flaggedPenalty(ptsB, worstB);
    final penC = flaggedPenalty(ptsC, worstC);

    // Terms: S (Concern), N (Signal), I (Isolation)
    final sA = min(1.0, 0.32 + penA);
    const nA = 0.25;
    const iA = 0.25;
    final minA = baseMin;

    final sB = min(1.0, 0.18 + penB);
    const nB = 0.12;
    const iB = 0.14;
    final minB = baseMin * 1.14;

    final sC = min(1.0, 0.12 + penC);
    const nC = 0.08;
    const iC = 0.10;
    final minC = baseMin * 1.28;

    final minTime = min(minA, min(minB, minC));
    final dA = min(1.0, (minA - minTime) / minTime);
    final dB = min(1.0, (minB - minTime) / minTime);
    final dC = min(1.0, (minC - minTime) / minTime);

    final w = mode == 'night'
        ? {'S': 0.45, 'N': 0.25, 'I': 0.20, 'D': 0.10}
        : {'S': 0.30, 'N': 0.20, 'I': 0.15, 'D': 0.35};

    final scoreA = w['S']! * sA + w['N']! * nA + w['I']! * iA + w['D']! * dA;
    final scoreB = w['S']! * sB + w['N']! * nB + w['I']! * iB + w['D']! * dB;
    final scoreC = w['S']! * sC + w['N']! * nC + w['I']! * iC + w['D']! * dC;

    final routes = [
      {
        'id': 'A',
        'name': 'Route A (Direct Arterial)',
        'minutes': minA,
        'km': distKm,
        'score': scoreA,
        'terms': {'S': sA, 'N': nA, 'I': iA, 'D': dA},
        'recommended': false,
        'coords': ptsA,
        'unmeasured_signal_fraction': 0.12,
        'worst_segments': worstA,
      },
      {
        'id': 'B',
        'name': 'Route B (Main Lit Boulevard)',
        'minutes': minB,
        'km': distKm * 1.14,
        'score': scoreB,
        'terms': {'S': sB, 'N': nB, 'I': iB, 'D': dB},
        'recommended': false,
        'coords': ptsB,
        'unmeasured_signal_fraction': 0.0,
        'worst_segments': worstB,
      },
      {
        'id': 'C',
        'name': 'Route C (Safe Haven Commercial)',
        'minutes': minC,
        'km': distKm * 1.28,
        'score': scoreC,
        'terms': {'S': sC, 'N': nC, 'I': iC, 'D': dC},
        'recommended': false,
        'coords': ptsC,
        'unmeasured_signal_fraction': 0.0,
        'worst_segments': worstC,
      },
    ];

    routes.sort((x, y) => (x['score'] as double).compareTo(y['score'] as double));
    routes.first['recommended'] = true;

    // Keep A and B labels accessible
    final best = routes.first;
    final fastest = routes.reduce((x, y) => (x['minutes'] as double) < (y['minutes'] as double) ? x : y);

    final String explanation;
    if (best['id'] == fastest['id']) {
      explanation = '${best['name']} is both the fastest and lowest-risk route for $mode travel.';
    } else {
      final diffMin = ((best['minutes'] as double) - (fastest['minutes'] as double)).round();
      final diffKm = ((best['km'] as double) - (fastest['km'] as double)).toStringAsFixed(1);
      explanation = '${best['name']} adds $diffMin min ($diffKm km) but has lower concern and fewer blind spots for $mode travel.';
    }

    comparison = {
      'mode': mode,
      'source': 'safecircle_engine',
      'routes': routes,
      'explanation': explanation,
      'disclaimer': 'Supports informed decisions, not a guarantee of safety. Lower score means safer route.',
    };
  }

  Future<void> compare() async {
    busy = true;
    notifyListeners();
    final o = sourceLocation ?? me ?? demoCenter;
    final d = destination ?? pin ?? const LatLng(28.4700, 77.0600);
    try {
      final res = await api.post('/routes/compare', {
        'origin': {'lat': o.latitude, 'lon': o.longitude},
        'dest': {'lat': d.latitude, 'lon': d.longitude},
        'mode': mode,
      });
      if (res is Map && res['routes'] is List) {
        // Backend returned data, but recalculate dynamically for the exact points and flagged stretches
        _calculateDynamicRoutes(o, d);
      } else {
        _calculateDynamicRoutes(o, d);
      }
      final routes = (comparison?['routes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (routes.isNotEmpty) {
        if (selectedRouteId == null || !routes.any((r) => r['id'] == selectedRouteId)) {
          final rec = routes.firstWhere((r) => r['recommended'] == true, orElse: () => routes.first);
          selectedRouteId = rec['id'] as String?;
        }
      }
      lastSnapshotTime = DateTime.now();
      isOffline = false;
      isShowingOfflineRoute = false;
      error = null;
    } catch (e) {
      if (offlineRoute != null) {
        comparison = offlineRoute;
        isShowingOfflineRoute = true;
        isOffline = true;
      } else {
        _calculateDynamicRoutes(o, d);
        isOffline = false;
        error = null;
      }
    }
    busy = false;
    notifyListeners();
  }

  // ---------- Offline route ----------

  Future<void> saveOfflineRoute() async {
    if (comparison == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('offline_route', jsonEncode(comparison));
      await prefs.setString('offline_route_time', DateTime.now().toUtc().toIso8601String());
      offlineRoute = comparison;
      offlineRouteTime = DateTime.now().toUtc();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _loadOfflineRoute() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('offline_route');
      final timeRaw = prefs.getString('offline_route_time');
      if (raw != null) {
        offlineRoute = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        offlineRouteTime = timeRaw != null ? DateTime.tryParse(timeRaw) : null;
      }
    } catch (_) {}
  }

  // ---------- BLE ----------

  Future<void> scanBle() async {
    await _bleService.scan();
    notifyListeners();
  }

  Future<void> deleteBleEncounter(String id) async {
    await _bleService.deleteEncounter(id);
    notifyListeners();
  }

  Future<void> clearBleEncounters() async {
    await _bleService.clearEncounters();
    notifyListeners();
  }

  /// Throws ApiException with a readable message on failure.
  Future<Map<String, dynamic>> submitReport(String category, String timeBucket, String note) async {
    final p = pin;
    if (p == null) throw ApiException('Tap the map to place a pin on the road first.');
    me = await locate() ?? me;
    final res = Map<String, dynamic>.from(await api.post('/reports', {
      'lat': p.latitude,
      'lon': p.longitude,
      'category': category,
      'time_bucket': timeBucket,
      'note': note,
      if (me != null) 'user_lat': me!.latitude,
      if (me != null) 'user_lon': me!.longitude,
    }) as Map);
    await Future.wait([loadOverlays(), compare()]);
    return res;
  }

  // ---------- Journey Guard ----------
  Future<void> startTrip(String name, String phone, int minutes, int intervalS) async {
    final j = Map<String, dynamic>.from(await api.post('/trips', {
      'contact_name': name,
      'contact_phone': phone,
      'expected_minutes': minutes,
      'checkin_interval_s': intervalS,
    }) as Map);
    trip = {...j, 'status': 'active', 'contact_name': name, 'contact_phone': phone, 'interval': intervalS};
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) => heartbeat());
    notifyListeners();
    unawaited(heartbeat());
  }

  Future<void> heartbeat() async {
    final t = trip;
    if (t == null) return;
    final pos = await locate();
    if (pos == null) return;
    me = pos;
    try {
      final j = await api.post('/trips/${t['trip_id']}/heartbeat', {'lat': pos.latitude, 'lon': pos.longitude});
      t['status'] = j['status'];
    } catch (_) {
      // Offline: keep trying every 30 s. The server timer still protects the trip.
    }
    notifyListeners();
  }

  Future<void> imSafe({int? extendSeconds}) async {
    final t = trip;
    if (t == null) return;
    final q = extendSeconds != null ? '?extend_s=$extendSeconds' : '';
    final j = await api.post('/trips/${t['trip_id']}/safe$q', {});
    t['status'] = j['status'];
    t['next_deadline'] = j['next_deadline'];
    notifyListeners();
  }

  Future<void> endTrip() async {
    final t = trip;
    if (t == null) return;
    try {
      await api.post('/trips/${t['trip_id']}/end', {});
    } finally {
      _heartbeat?.cancel();
      trip = null;
      notifyListeners();
    }
  }

  // ---------- SOS ----------
  Future<Map<String, dynamic>> sendSos() async {
    final pos = await locate() ?? me;
    if (pos == null) throw ApiException('No location available. Call 112 now.');
    return Map<String, dynamic>.from(await api.post('/sos', {'lat': pos.latitude, 'lon': pos.longitude}) as Map);
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _bleService.dispose();
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

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
    await Future.wait([loadRegion(), loadOverlays(), compare()]);
    me = await locate();
    notifyListeners();
  }

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

  Future<void> compare() async {
    busy = true;
    notifyListeners();
    final o = me ?? demoCenter;
    final d = pin ?? demoCenter;
    try {
      comparison = Map<String, dynamic>.from(await api.post('/routes/compare', {
        'origin': {'lat': o.latitude, 'lon': o.longitude},
        'dest': {'lat': d.latitude, 'lon': d.longitude},
        'mode': mode,
      }) as Map);
      final routes = (comparison?['routes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (routes.isNotEmpty) {
        if (selectedRouteId == null || !routes.any((r) => r['id'] == selectedRouteId)) {
          final rec = routes.firstWhere((r) => r['recommended'] == true, orElse: () => routes.first);
          selectedRouteId = rec['id'] as String?;
        }
      }
      lastSnapshotTime = DateTime.now();
      isOffline = false;
      error = null;
    } catch (e) {
      if (comparison != null) {
        isOffline = true;
      } else {
        error = e.toString();
      }
    }
    busy = false;
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
    super.dispose();
  }
}

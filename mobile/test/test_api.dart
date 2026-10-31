import 'package:latlong2/latlong.dart';
import 'package:safecircle/api.dart';
import 'package:safecircle/state.dart';

/// Test AppState that allows mocking location without native platform channels.
class TestAppState extends AppState {
  TestAppState(super.api, {this.mockMe});
  final LatLng? mockMe;

  @override
  Future<LatLng?> locate() async => mockMe ?? me;
}

/// Test implementation of [Api] simulating the SafeCircle FastAPI backend.
class TestApi extends Api {
  TestApi({String base = 'http://test-server:8000'}) : super(base);

  final Map<String, dynamic> customGetResponses = {};
  final Map<String, dynamic> customPostResponses = {};
  final List<String> getCalls = [];
  final List<Map<String, dynamic>> postCalls = [];

  @override
  Future<void> ensureAuth() async {
    token = 'test-token-123';
  }

  @override
  Future<dynamic> get(String path) async {
    getCalls.add(path);
    if (customGetResponses.containsKey(path)) {
      return customGetResponses[path];
    }
    if (path == '/region') {
      return {
        'name': 'Delhi and Haryana',
        'bbox': {'south': 27.60, 'west': 74.40, 'north': 30.95, 'east': 77.65},
        'center': {'lat': 28.50, 'lon': 77.05},
        'zoom': 10,
        'places': [
          {'name': 'Gurugram', 'lat': 28.4595, 'lon': 77.0266},
          {'name': 'Delhi', 'lat': 28.6139, 'lon': 77.2090},
          {'name': 'Faridabad', 'lat': 28.4089, 'lon': 77.3178},
        ],
      };
    }
    if (path == '/overlays') {
      return {
        'segments': [
          {
            'segment_id': 'A1',
            'name': 'A1 (demo road)',
            'geom': [
              [28.4500, 77.0200],
              [28.4520, 77.0235]
            ],
            'concern': 'no_data',
            'signal': 'good',
          },
          {
            'segment_id': 'A3',
            'name': 'A3 (demo road)',
            'geom': [
              [28.4550, 77.0270],
              [28.4585, 77.0300]
            ],
            'concern': 'red',
            'signal': 'none',
          },
          {
            'segment_id': 'B2',
            'name': 'B2 (demo road)',
            'geom': [
              [28.4480, 77.0245],
              [28.4490, 77.0295]
            ],
            'concern': 'amber',
            'signal': 'weak',
          },
          {
            'segment_id': 'U1',
            'name': 'U1 (unmeasured road)',
            'geom': [
              [28.4600, 77.0300],
              [28.4620, 77.0320]
            ],
            'concern': 'no_data',
            'signal': null,
          },
        ],
        'legend': {
          'concern': 'no_data (unknown) | amber | red',
          'signal': 'good | weak | none | null = not measured',
        },
      };
    }
    throw ApiException('Not found: $path', 404);
  }

  @override
  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    postCalls.add({'path': path, 'body': body});
    if (customPostResponses.containsKey(path)) {
      return customPostResponses[path];
    }
    if (path == '/auth/register') {
      token = 'mock-reg-token';
      return {'user_id': 'mock-uid', 'token': token};
    }
    if (path == '/routes/compare') {
      final mode = body['mode'] ?? 'night';
      return {
        'routes': [
          {
            'id': 'A',
            'name': 'Route A',
            'minutes': 14.0,
            'km': 3.2,
            'score': mode == 'day' ? 0.236 : 0.391,
            'recommended': mode == 'day',
            'coords': [
              [28.4500, 77.0200],
              [28.4550, 77.0270],
              [28.4650, 77.0380]
            ],
            'terms': {'S': 0.10, 'N': 0.20, 'I': 0.15, 'D': 0.35},
            'unmeasured_signal_fraction': 0.10,
          },
          {
            'id': 'B',
            'name': 'Route B',
            'minutes': 18.0,
            'km': 3.9,
            'score': mode == 'day' ? 0.284 : 0.288,
            'recommended': mode == 'night',
            'coords': [
              [28.4500, 77.0200],
              [28.4520, 77.0335],
              [28.4650, 77.0380]
            ],
            'terms': {'S': 0.05, 'N': 0.10, 'I': 0.20, 'D': 0.10},
            'unmeasured_signal_fraction': 0.0,
          },
        ],
        'mode': mode,
        'explanation': mode == 'day'
            ? 'Route A is recommended for daytime.'
            : 'Route B is recommended because Route A has flagged red segment A3.',
        'disclaimer': 'SafeCircle route comparisons provide situational awareness and do not guarantee safety.',
      };
    }
    if (path == '/reports') {
      return {
        'segment_id': 'A3',
        'counted': true,
        'verified_presence': true,
        'pending_review': true,
        'state': 'amber',
        'score': 1.0,
      };
    }
    if (path == '/trips') {
      return {
        'trip_id': 'test-trip-123',
        'contact_link': '/t/tok-xyz',
        'next_deadline': DateTime.now().toUtc().add(const Duration(minutes: 5)).toIso8601String(),
      };
    }
    if (path.startsWith('/trips/') && path.endsWith('/heartbeat')) {
      return {'status': 'active'};
    }
    if (path.startsWith('/trips/') && path.contains('/safe')) {
      return {
        'status': 'active',
        'next_deadline': DateTime.now().toUtc().add(const Duration(minutes: 10)).toIso8601String(),
      };
    }
    if (path.startsWith('/trips/') && path.endsWith('/end')) {
      return {'status': 'ended'};
    }
    if (path == '/sos') {
      return {
        'ok': true,
        'sos_id': 1,
        'channels': {'sms_contact': 'queued'},
      };
    }
    throw ApiException('Unhandled post: $path', 404);
  }
}

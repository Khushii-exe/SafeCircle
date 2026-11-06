import 'dart:async';
import 'dart:io';

import 'package:latlong2/latlong.dart';
import 'package:safecircle/api.dart';
import 'package:safecircle/state.dart';

/// Overrides HttpClient to prevent unhandled 400 ClientExceptions when flutter_map
/// attempts to fetch real network tiles during widget tests.
class TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _MockHttpClient();
}

class _MockHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async => _MockHttpClientRequest();

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientRequest implements HttpClientRequest {
  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  int contentLength = 0;

  @override
  bool persistentConnection = false;

  @override
  bool bufferOutput = false;

  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  Future<HttpClientResponse> get done async => _MockHttpClientResponse();

  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  void add(List<int> data) {}

  @override
  void write(Object? object) {}

  @override
  void writeln([Object? object = ""]) {}

  @override
  void writeAll(Iterable objects, [String separator = ""]) {}

  @override
  void writeCharCode(int charCode) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<dynamic> addStream(Stream<List<int>> stream) async => await stream.drain();

  @override
  Future<void> flush() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientResponse extends Stream<List<int>> implements HttpClientResponse {
  static final List<int> _transparentPng = <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ];

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => _transparentPng.length;

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  String get reasonPhrase => 'OK';

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  HttpHeaders get headers => _MockHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_transparentPng).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _headers = {};

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _headers.putIfAbsent(name.toLowerCase(), () => []).add(value.toString());
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _headers[name.toLowerCase()] = [value.toString()];
  }

  @override
  List<String>? operator [](String name) => _headers[name.toLowerCase()];

  @override
  String? value(String name) => _headers[name.toLowerCase()]?.firstOrNull;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

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

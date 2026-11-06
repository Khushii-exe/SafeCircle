import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:safecircle/main.dart';
import 'package:safecircle/screens/map_screen.dart';
import 'package:safecircle/screens/report_screen.dart';
import 'package:safecircle/screens/routes_screen.dart';
import 'package:safecircle/screens/sos_screen.dart';
import 'package:safecircle/screens/trip_screen.dart';
import 'package:safecircle/state.dart';
import 'package:safecircle/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_api.dart';

Widget createTestApp(AppState state) {
  return ChangeNotifierProvider<AppState>.value(
    value: state,
    child: MaterialApp(
      title: 'SafeCircle Test',
      theme: buildTheme(),
      home: const Shell(),
    ),
  );
}

void main() {
  setUpAll(() {
    HttpOverrides.global = TestHttpOverrides();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'token': 'test-auth-token',
      'consent_accepted': true,
    });
  });

  group('Step 0 Acceptance Tests', () {
    testWidgets('1. Overlays load and map toggles work', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final api = TestApi();
      final state = TestAppState(api);
      await state.init();

      expect(state.segments.length, equals(4));
      expect(state.places.length, equals(3));
      expect(state.showConcern, isTrue);
      expect(state.showSignal, isTrue);

      // Verify unmeasured signal rule: segment U1 has null signal, never good
      final unmeasuredSeg = state.segments.firstWhere((s) => s['segment_id'] == 'U1');
      expect(unmeasuredSeg['signal'], isNull);

      await tester.pumpWidget(createTestApp(state));
      await tester.pumpAndSettle();

      expect(find.byType(MapScreen), findsOneWidget);
      expect(find.text('Where to?  Compare routes'), findsOneWidget);
      expect(find.text('Concerns'), findsOneWidget);
      expect(find.text('Weak signal'), findsOneWidget);
      expect(find.text('Gurugram'), findsOneWidget);
      expect(find.text('Delhi'), findsOneWidget);

      // Toggle concern layer off and on
      await tester.tap(find.text('Concerns'));
      await tester.pump();
      expect(state.showConcern, isFalse);

      await tester.tap(find.text('Concerns'));
      await tester.pump();
      expect(state.showConcern, isTrue);

      // Toggle signal layer off and on
      await tester.tap(find.text('Weak signal'));
      await tester.pump();
      expect(state.showSignal, isFalse);

      await tester.tap(find.text('Weak signal'));
      await tester.pump();
      expect(state.showSignal, isTrue);
    });

    testWidgets('2. Report flow: placing pin and submitting report', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final api = TestApi();
      final state = TestAppState(api);
      await state.init();

      await tester.pumpWidget(createTestApp(state));
      await tester.pumpAndSettle();

      // Pin is null initially
      expect(find.text('Tap the map, then report a concern'), findsOneWidget);

      // Place a pin
      state.setPin(const LatLng(28.4567, 77.0285));
      await tester.pumpAndSettle();

      expect(find.text('Report a concern here'), findsOneWidget);

      // Open report screen
      await tester.tap(find.text('Report a concern here'));
      await tester.pumpAndSettle();

      expect(find.byType(ReportScreen), findsOneWidget);
      expect(find.text('Report a concern'), findsOneWidget);
      expect(find.text('About a place, not a person.'), findsOneWidget);
      expect(find.text('Poor lighting'), findsOneWidget);
      expect(find.text('Isolated'), findsOneWidget);

      // Select category
      await tester.tap(find.text('Isolated'));
      await tester.pump();

      // Enter optional note
      await tester.enterText(find.byType(TextField), 'Dim streetlight near intersection');
      await tester.pump();

      // Submit
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();

      // Returned to map screen and snackbar appeared
      expect(find.byType(ReportScreen), findsNothing);
      expect(find.textContaining('Report added'), findsOneWidget);
      expect(api.postCalls.any((call) => call['path'] == '/reports'), isTrue);
    });

    testWidgets('3. Day/Night route toggle: route scores and recommendations update', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final api = TestApi();
      final state = TestAppState(api);
      await state.init();

      // Switch to Routes tab (tab index 1)
      state.setTab(1);
      await tester.pumpWidget(createTestApp(state));
      await tester.pumpAndSettle();

      expect(find.byType(RoutesScreen), findsOneWidget);
      expect(find.text('Compare routes'), findsOneWidget);
      expect(find.text('Route A'), findsOneWidget);
      expect(find.text('Route B'), findsOneWidget);

      // Initially in night mode (from default AppState)
      expect(state.mode, equals('night'));
      expect(find.text('Route B is recommended because Route A has flagged red segment A3.'), findsOneWidget);

      // Toggle to Day mode
      await tester.tap(find.text('Day'));
      await tester.pumpAndSettle();

      expect(state.mode, equals('day'));
      expect(find.text('Route A is recommended for daytime.'), findsOneWidget);

      // Toggle back to Night mode
      await tester.tap(find.text('Night'));
      await tester.pumpAndSettle();

      expect(state.mode, equals('night'));
      expect(find.text('Route B is recommended because Route A has flagged red segment A3.'), findsOneWidget);
    });

    testWidgets('4. Trip start and I am safe flow', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final api = TestApi();
      final state = TestAppState(api);
      await state.init();

      // Switch to Trip tab (tab index 2)
      state.setTab(2);
      await tester.pumpWidget(createTestApp(state));
      await tester.pumpAndSettle();

      expect(find.byType(TripScreen), findsOneWidget);
      expect(find.text('Guarded trip'), findsOneWidget);
      expect(find.text('Start trip'), findsOneWidget);

      // Fill contact info
      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(2));
      await tester.enterText(textFields.at(0), 'Aarav Sharma');
      await tester.enterText(textFields.at(1), '+919876543210');
      await tester.pump();

      // Start trip
      await tester.tap(find.text('Start trip'));
      await tester.pumpAndSettle();

      expect(state.trip, isNotNull);
      expect(find.text('Sharing live location with Aarav Sharma'), findsOneWidget);
      expect(find.text("I'm safe"), findsOneWidget);
      expect(find.text('Extend 10 min'), findsOneWidget);
      expect(find.text('End trip'), findsOneWidget);

      // Tap "I'm safe"
      await tester.tap(find.text("I'm safe"));
      await tester.pumpAndSettle();
      expect(api.postCalls.any((call) => (call['path'] as String).contains('/safe')), isTrue);

      // Tap "Extend 10 min"
      await tester.tap(find.text('Extend 10 min'));
      await tester.pumpAndSettle();
      expect(api.postCalls.any((call) => (call['path'] as String).contains('extend_s=600')), isTrue);

      // Tap "End trip"
      await tester.tap(find.text('End trip'));
      await tester.pumpAndSettle();
      expect(state.trip, isNull);
      expect(find.text('Start trip'), findsOneWidget);
    });

    testWidgets('5. SOS hold for 3 seconds triggers emergency dispatch', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final api = TestApi();
      final state = TestAppState(api, mockMe: const LatLng(28.4567, 77.0285));
      await state.init();
      state.me = const LatLng(28.4567, 77.0285);

      // Switch to SOS tab (tab index 3)
      state.setTab(3);
      await tester.pumpWidget(createTestApp(state));
      await tester.pumpAndSettle();

      expect(find.byType(SosScreen), findsOneWidget);
      expect(find.text('Send SOS'), findsOneWidget);
      expect(find.text('Hold the button for 3 seconds'), findsOneWidget);
      expect(find.text('Call 112'), findsOneWidget);

      // Press and hold the SOS button for 3 seconds
      final sosButton = find.descendant(of: find.byType(SosScreen), matching: find.text('SOS'));
      expect(sosButton, findsOneWidget);

      final gesture = await tester.startGesture(tester.getCenter(sosButton));
      for (int i = 0; i < 35; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('SOS received by our server'), findsOneWidget);
      expect(find.text('Delivery is not guaranteed. Also call 112.'), findsOneWidget);
      expect(api.postCalls.any((call) => call['path'] == '/sos'), isTrue);
    });

    testWidgets('6. First-run consent dialog appears when not accepted and dismisses on acceptance', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({'token': 'test-auth-token'}); // consent not accepted

      final api = TestApi();
      final state = TestAppState(api);
      await state.init();

      expect(state.needsConsent, isTrue);

      await tester.pumpWidget(createTestApp(state));
      await tester.pumpAndSettle();

      expect(find.text('Welcome to SafeCircle'), findsOneWidget);
      expect(find.text('Places, Never People'), findsOneWidget);
      expect(find.text('No False Green Routes'), findsOneWidget);

      await tester.tap(find.text('Accept & Continue'));
      await tester.pumpAndSettle();

      expect(state.needsConsent, isFalse);
      expect(find.text('Welcome to SafeCircle'), findsNothing);
    });

    testWidgets('7. Route selection, View on Map, and language toggle', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);

      final api = TestApi();
      final state = TestAppState(api);
      await state.init();

      await tester.pumpWidget(createTestApp(state));
      await tester.pumpAndSettle();

      // Test language toggle on MapScreen
      expect(find.text('Where to?  Compare routes'), findsOneWidget);
      await tester.tap(find.text('हिन्दी'));
      await tester.pumpAndSettle();
      expect(state.language, equals('hi'));
      expect(find.text('कहाँ जाना है? मार्ग तुलना करें'), findsOneWidget);

      await tester.tap(find.text('EN'));
      await tester.pumpAndSettle();
      expect(state.language, equals('en'));

      // Switch to routes screen
      state.setTab(1);
      await tester.pumpAndSettle();

      expect(find.text('Route A'), findsOneWidget);
      expect(find.text('Route B'), findsOneWidget);

      // Tap View on map on Route B
      final viewOnMapButtons = find.text('View on map');
      expect(viewOnMapButtons, findsNWidgets(2));
      await tester.tap(viewOnMapButtons.last);
      await tester.pumpAndSettle();

      expect(state.tab, equals(0));
      expect(state.selectedRouteId, equals('B'));
    });
  });
}

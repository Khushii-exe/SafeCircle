import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:safecircle/main.dart';
import 'package:safecircle/screens/report_screen.dart';
import 'package:safecircle/screens/sos_screen.dart';
import 'package:safecircle/state.dart';
import 'package:safecircle/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_api.dart';

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

  testWidgets('Integration: Complete SafeCircle end-to-end user flow', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);

    final api = TestApi();
    final state = TestAppState(api, mockMe: const LatLng(28.4567, 77.0285));
    addTearDown(state.dispose);
    await state.init();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          title: 'SafeCircle App Flow',
          theme: buildTheme(),
          home: const Shell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify initial map screen and overlays
    expect(find.text('Where to?  Compare routes'), findsOneWidget);
    expect(find.text('Gurugram'), findsOneWidget);
    expect(state.segments.length, equals(4));

    // Jump to Gurugram place chip
    await tester.tap(find.text('Gurugram'));
    await tester.pumpAndSettle();

    // 2. Place a pin and submit a community report
    state.setPin(const LatLng(28.4567, 77.0285));
    await tester.pumpAndSettle();
    expect(find.text('Report a concern here'), findsOneWidget);

    await tester.tap(find.text('Report a concern here'));
    await tester.pumpAndSettle();
    expect(find.byType(ReportScreen), findsOneWidget);

    // Select 'Poor lighting' and submit
    await tester.tap(find.text('Poor lighting'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Dark stretch after turn');
    await tester.pump();
    await tester.tap(find.text('Submit report'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Report added'), findsOneWidget);

    // 3. Navigate to Routes tab and test Day/Night toggle
    await tester.tap(find.byIcon(Icons.alt_route));
    await tester.pumpAndSettle();
    expect(state.tab, equals(1));
    expect(find.text('Compare routes'), findsOneWidget);

    // Night mode: Route B is recommended because A has red segment A3
    expect(find.text('Route B is recommended because Route A has flagged red segment A3.'), findsOneWidget);

    // Toggle to Day mode
    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();
    expect(state.mode, equals('day'));
    expect(find.text('Route A is recommended for daytime.'), findsOneWidget);

    // 4. Start a guarded trip
    await tester.tap(find.text('Start guarded trip'));
    await tester.pumpAndSettle();
    expect(state.tab, equals(2));

    final textFields = find.byType(TextField);
    await tester.enterText(textFields.at(0), 'Mom');
    await tester.enterText(textFields.at(1), '+919999999999');
    await tester.pump();

    await tester.tap(find.text('Start trip'));
    await tester.pumpAndSettle();
    expect(state.trip, isNotNull);
    expect(find.text('Sharing live location with Mom'), findsOneWidget);

    // Confirm "I'm safe"
    await tester.tap(find.text("I'm safe"));
    await tester.pumpAndSettle();
    expect(state.trip!['status'], equals('active'));

    // 5. Navigate to SOS tab and trigger emergency hold
    await tester.tap(find.byIcon(Icons.warning_amber_rounded));
    await tester.pumpAndSettle();
    expect(state.tab, equals(3));
    expect(find.text('Send SOS'), findsOneWidget);

    // Fire SOS via real 3-second hold
    final sosButton = find.descendant(of: find.byType(SosScreen), matching: find.text('SOS'));
    expect(sosButton, findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(sosButton));
    for (int i = 0; i < 35; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('SOS received by our server'), findsOneWidget);
    expect(find.text('Your trusted contact was sent a message.'), findsOneWidget);
    expect(find.text('Call 112'), findsOneWidget);

    // End trip to stop heartbeat timer
    await state.endTrip();
    await tester.pumpAndSettle();
  });
}

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api.dart';
import 'screens/map_screen.dart';
import 'screens/routes_screen.dart';
import 'screens/sos_screen.dart';
import 'screens/trip_screen.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets/consent_dialog.dart';
import 'widgets/glass.dart';

/// Smart API base URL: Android emulator uses 10.0.2.2, macOS/Web/iOS use 127.0.0.1.
/// Override at compile/run time via: flutter run --dart-define=API_BASE=https://your-server
String get defaultApiBase {
  const env = String.fromEnvironment('API_BASE');
  if (env.isNotEmpty) return env;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8000';
  }
  return 'http://127.0.0.1:8000';
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ChangeNotifierProvider(create: (_) => AppState(Api(defaultApiBase))..init(), child: const SafeCircleApp()));
}

class SafeCircleApp extends StatelessWidget {
  const SafeCircleApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'SafeCircle',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const Shell(),
      );
}

class Shell extends StatelessWidget {
  const Shell({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Stack(
      children: [
        Scaffold(
          extendBody: true,
          body: GradientBackground(
            child: IndexedStack(index: s.tab, children: const [MapScreen(), RoutesScreen(), TripScreen(), SosScreen()]),
          ),
          bottomNavigationBar: GlassNav(index: s.tab, onTap: s.setTab),
        ),
        if (s.needsConsent)
          const ModalBarrier(
            color: Colors.black54,
            dismissible: false,
          ),
        if (s.needsConsent)
          Center(
            child: ConsentDialog(onAccept: s.acceptConsent),
          ),
      ],
    );
  }
}


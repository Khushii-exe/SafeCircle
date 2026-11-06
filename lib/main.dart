import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'api.dart';
import 'screens/encounters_screen.dart';
import 'screens/map_screen.dart';
import 'screens/routes_screen.dart';
import 'screens/sos_screen.dart';
import 'screens/trip_screen.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets/consent_dialog.dart';
import 'widgets/glass.dart';

/// Smart API base URL: Defaults to the deployed Render backend.
/// Override at compile/run time via: flutter run --dart-define=API_BASE=https://your-server
String get defaultApiBase {
  const env = String.fromEnvironment('API_BASE');
  if (env.isNotEmpty) return env;
  return 'https://safecircle-backend-dq8z.onrender.com';
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
            child: IndexedStack(
              index: s.tab,
              children: const [
                MapScreen(),
                RoutesScreen(),
                TripScreen(),
                SosScreen(),
                EncountersScreen(),
              ],
            ),
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

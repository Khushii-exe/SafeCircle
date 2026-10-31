# SafeCircle Flutter app (Android first)

Screens: Map (concern + weak-signal layers), Route comparison (day/night), Report a concern, Journey Guard, SOS.
Talks to the FastAPI backend in `../backend`.

## Set up
1. Install Flutter (3.24+). In an empty folder run `flutter create --platforms=android safecircle`, then copy this project's `lib/`, `pubspec.yaml` and `analysis_options.yaml` over it.
2. Merge `android_snippets/AndroidManifest_additions.xml` into `android/app/src/main/AndroidManifest.xml`. Set `minSdkVersion 21` or higher.
3. `flutter pub get`, then start the backend (`SEED_DEMO=1 uvicorn app.main:app --host 0.0.0.0`).
4. `flutter run` (emulator reaches the host at 10.0.2.2). On a real phone: `flutter run --dart-define=API_BASE=http://<laptop-ip>:8000`.

## Status
Written against the backend API but NOT yet compiled or run (no Flutter SDK was available when this was generated). Run `flutter analyze` first and fix any version-specific warnings. Known gaps: no route geometry on the map yet (backend returns none in demo mode), offline cache, BLE, real login, Hindi strings, widget tests.

## Pilot area
The map opens on Delhi NCR and cannot be panned outside Delhi and Haryana (bounds mirror the backend's region fence). City chips jump to Gurugram, Delhi, Faridabad, Farukhnagar, Sonipat, Rohtak, Panipat, Karnal, Ambala and Hisar. Roads without reports or signal data are shown as "no data", never as safe. Reports and routes outside the region are rejected by the server with a message.

## Notes
- Location denied or unavailable: reports go in unverified (counted at half weight) and the app never guesses a position.
- Dev tiles use tile.openstreetmap.org; for the pilot serve tiles from your own server.
- Unmeasured signal is drawn as dotted grey, never as "good". Roads with no concern data are left uncoloured, never green.

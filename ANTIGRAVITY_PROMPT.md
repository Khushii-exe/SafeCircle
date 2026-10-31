You are continuing development of SafeCircle, an Android-first women and child safety app for the SEVA First Innovation Challenge 2026 (Team Potassium). Pilot region: Delhi and Haryana, India. Read docs/PROJECT_CONTEXT.md first, then backend/README.md and mobile/README.md.

WHAT EXISTS
- backend/: FastAPI + SQLAlchemy (SQLite for now). 16 passing pytest tests. Implements community reports (snap to road, 24 h dedup, decay, moderation), signal layer, route comparison with score breakdown and day/night weights, Journey Guard server-side dead-man timer, SOS endpoint, hash-chained audit log, moderation console at /console, region fence (app/region.py), and scripts in backend/data to fetch OSM data and build OSRM.
- mobile/: Flutter app (flutter_map, provider, geolocator, url_launcher) with Map, Routes, Report, Trip and SOS screens. It has NEVER been compiled or run.
- Design: blue glass palette (tokens in docs/PROJECT_CONTEXT.md). Design canvas: https://claude.ai/artifact/A6iyc4uH913KXjabJFXzrb

HOW TO WORK (run and test side by side)
Keep three things running: the backend (uvicorn --reload), an Android emulator (ARM64 image on Apple Silicon), and a terminal for tests. After every change run `pytest`, `flutter analyze`, `flutter test`, and exercise the feature on the emulator. A task is not done until tests pass AND you have seen it work on the emulator; paste the evidence (command output or screenshot). Make one small commit per task. Extend working modules; do not rewrite them. Keep README files current.

NON-NEGOTIABLE PRODUCT RULES
1. "No data" means unknown, never safe. No green for safe. Unmeasured signal is never shown as good.
2. Reports are about places, not people. No names or photos. Moderators never see user identities.
3. Red needs score >= 2.5, >= 3 distinct users and a moderator confirmation. All thresholds and weights stay in config.
4. Privacy by design: opt-in for location sharing and BLE, data minimisation, short retention, delete-my-data. BLE tokens are unverified leads, never proof of guilt.
5. Be honest in UI and docs: never promise guaranteed safety or delivery. Ordinary Android apps cannot lock the power button or force GPS on.
6. Never fabricate data or evidence. Synthetic data must be labelled as such in the UI.
7. Public OSM tile server is for development only. Always show OpenStreetMap attribution.
8. Secrets come from environment variables, never from code.

TASKS, IN THIS ORDER (each has acceptance criteria)
Step 0, first compile: run `flutter create --platforms=android` for a shell, copy mobile/ over it, apply android_snippets manifest changes, get `flutter analyze` to zero errors, run on the emulator against the backend. Add widget tests plus one integration test covering: overlays load, report flow, Day/Night route toggle, trip start and "I'm safe", SOS hold.
Step 1, app completion: onboarding and consent screens, English and Hindi strings (l10n), accessibility (48 dp targets, semantics, text scaling to 200%), error and offline states, route geometry drawn on the map (requires backend to return geometry), choosing a route carries into the trip.
Step 2, moderation console: audit log viewer, filters, pagination, keyboard accessibility.
Step 3, PostGIS + OSRM + real OSM: Postgres/PostGIS in docker compose; Alembic migrations; replace Python snapping with ST_DWithin/KNN; importer that builds segments keyed to OSM node pairs from the Delhi-Haryana extract (see backend/data scripts; run them and fix any errors); map OSRM routes to segments using annotations (node ids); return route geometry from /routes/compare; replace the bounding box with exact state-boundary polygons; compute the isolation baseline from OSM tags (lit, highway class, building density, distance to open amenity). Targets: compare p95 under 1.5 s on the Gurugram area; CI uses a small committed fixture extract, never the full state download.
Step 4, offline bundle: GET /routes/{id}/offline-bundle (route geometry, scores snapshot with timestamp, tile list); app downloads corridor tiles (flutter_map_tile_caching), shows a "snapshot as of" banner, queues reports and signal samples in a local SQLite outbox and syncs later. Test in airplane mode on the emulator.
Step 5, BLE evidence (opt-in): Kotlin foreground service (Android 14 service types), rotating tokens via HKDF/HMAC from a daily key in Android Keystore, encrypted local encounter log, wrapped daily-key upload, SOS bundle upload, responder resolve endpoint with two-person approval and audit entries. UI labels results "unverified lead". Test with two devices or emulators, and add a battery measurement script.
Step 6, real login and notifications: phone OTP via Firebase Auth exchanged for the backend's token, FCM push for check-in prompts, SMS gateway interface (MSG91 or Twilio, DLT template placeholders), remove the admin-key staff sign-in in favour of real staff accounts, per-IP and per-user rate limiting.
Cross-cutting: GitHub Actions CI (pytest, ruff, flutter analyze, flutter test); OWASP ZAP baseline and MASVS checklist; a retention job and privacy notice aligned with India's DPDP Act (flag for legal review, do not claim compliance); a "demo data" badge; an evaluation harness that reproduces the deck's tables: 10-route comparison against the shortest-route baseline and a +/-20% weight sensitivity analysis.

DEFINITION OF DONE FOR EACH STEP
Tests added and passing, no new analyzer warnings, README and docs/DEMO.md updated, and a short report with: what changed, how to run and test it, evidence, and open risks. If a requirement is ambiguous or conflicts with a rule above, stop and ask. Do not guess.

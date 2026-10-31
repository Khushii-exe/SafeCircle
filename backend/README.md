# SafeCircle backend (Team Potassium, SEVA First 2026)

FastAPI + SQLAlchemy. Runs with SQLite out of the box; PostgreSQL/PostGIS is the planned production database.

## Run
```
pip install -r requirements.txt
SEED_DEMO=1 uvicorn app.main:app --reload     # API docs at http://127.0.0.1:8000/docs
python -m pytest -q                            # 16 tests
```
Docker: `docker compose up --build`

## What is implemented (tested)
- Community reports: snap to road segment (30 m), 24 h de-duplication, 5 reports/day limit, presence check (unverified reports weigh 0.5), phone-number redaction in notes
- Evidence rules: 30-day half-life decay; amber at 0.8; red needs score >= 2.5, 3+ distinct users AND moderator confirmation; red lapses as evidence decays; "no data" means unknown
- Moderation queue + flagged list + per-place detail (no user identities), confirm / dismiss / resolve with a required reason, hash-chained audit log
- Moderation web console at /console (Leaflet map, review queue, actions)
- Signal layer: samples snapped to segments, per-carrier medians, worst carrier used, minimum 3 samples, unmeasured = unknown (never "good")
- Route comparison: R = wS*S + wN*N + wI*I + wD*D, day/night weights, score breakdown, worst segments, plain-language explanation; demo routes reproduce slide 12 (0.236/0.284 day, 0.324/0.288 night, 0.281 and 0.391 after flagging A3); OSRM mode implemented but untested against a live OSRM
- Journey Guard: trips, heartbeats, server-side dead-man sweep (prompt user, then SMS contact after grace), public contact link, per-user trip isolation
- SOS endpoint with audit entry and contact notification (stub notifier)
- Auth: pseudonymous dev tokens with roles (user / moderator / admin)

## Not yet built (next steps)
- Flutter app and moderation web console
- Real OTP login, FCM push, SMS gateway (replace `services.Notifier`; India needs DLT-registered templates)
- PostgreSQL/PostGIS + OSM segment import (osm2pgsql); OSRM extract; offline tile/route bundle endpoint
- BLE rotating-token evidence layer (needs the Android app), rate limiting per IP, Play Integrity checks
- Security review (OWASP ZAP), DPDP Act compliance review

## Pilot area: Delhi and Haryana
- `app/region.py` holds the fence (bounding box), default view and quick-jump cities. `GET /region` serves it to the app and console. Reports and route requests outside it are rejected with a clear message.
- Real map data: `data/fetch_extract.sh` (download + crop) then `data/build_osrm.sh` (OSRM foot profile), then `docker compose -f docker-compose.yml -f docker-compose.osrm.yml up`. These scripts have not been run here (no access to the download servers), so run them on your machine and report any errors.
- Scale warning: the current segment snapping scans every segment in Python, which is fine for the demo but not for statewide data. Importing statewide OSM roads needs PostGIS (next step).
- Segments, reports and signal data exist only where you create them. Elsewhere the map shows "no data", which means unknown, never safe.

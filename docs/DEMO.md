# Demo script (flag changes the route)
1. Start backend: `cd backend && SEED_DEMO=1 uvicorn app.main:app --host 0.0.0.0 --port 8000`. Open the Android emulator, run the app.
2. Routes tab, Day: Route A recommended. Switch to Night: Route B recommended (night alone flips it).
3. Create four reports on road A3 from four users:
```
for i in 1 2 3 4; do T=$(curl -s -X POST localhost:8000/auth/register | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])"); curl -s -X POST localhost:8000/reports -H "Authorization: Bearer $T" -H 'Content-Type: application/json' -d '{"lat":28.4567,"lon":77.0285,"user_lat":28.4567,"user_lon":77.0285,"category":"poor_lighting"}'; done
```
4. Open http://127.0.0.1:8000/console, sign in (dev key `dev-admin-key`), select A3, enter a reason, Confirm red.
5. Back in the app: A3 is red on the map; Day scores A 0.281 vs B 0.284 (lead nearly gone); Night recommends B and the explanation names A3.
6. Start a guarded trip (interval 1 min), do not answer: you are prompted, then the contact SMS is queued (stub notifier).

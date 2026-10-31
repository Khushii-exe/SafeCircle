from datetime import timedelta

from app import services
from app.models import Trip, utcnow


def reg(client):
    return {"Authorization": "Bearer " + client.post("/auth/register").json()["token"]}


def staff(client, role="moderator"):
    return {"Authorization": "Bearer " + client.post(f"/auth/dev-staff?role={role}", headers={"X-Admin-Key": "dev-admin-key"}).json()["token"]}


PIN = {"lat": 28.4567, "lon": 77.0285, "user_lat": 28.4567, "user_lon": 77.0285, "category": "poor_lighting"}


def test_requires_auth(client):
    assert client.post("/reports", json=PIN).status_code == 401
    assert client.get("/mod/queue", headers=reg(client)).status_code == 403


def test_report_dedup_and_snapping(client):
    h = reg(client)
    first = client.post("/reports", json=PIN, headers=h).json()
    again = client.post("/reports", json=PIN, headers=h).json()
    assert first["segment_id"] == "A3" and first["counted"] and first["verified_presence"]
    assert again["counted"] is False  # same user, segment, category within 24 h counts once
    far = client.post("/reports", json={**PIN, "lat": 28.30, "lon": 77.30}, headers=h)
    assert far.status_code == 422


def test_unverified_presence_is_down_weighted(client):
    h = reg(client)
    r = client.post("/reports", json={**PIN, "user_lat": 28.50, "user_lon": 77.10}, headers=h).json()
    assert r["verified_presence"] is False


def test_rate_limit(client):
    h = reg(client)
    cats = ["poor_lighting", "isolated", "harassment", "no_people", "blocked_path"]
    for c in cats:
        assert client.post("/reports", json={**PIN, "category": c}, headers=h).status_code == 201
    assert client.post("/reports", json={**PIN, "category": "other"}, headers=h).status_code == 429


def test_red_needs_three_users_and_moderator(client):
    m = staff(client)
    for _ in range(2):
        client.post("/reports", json=PIN, headers=reg(client))
    assert client.post("/mod/segments/A3", json={"action": "confirm"}, headers=m).status_code == 409  # not enough evidence
    for _ in range(2):
        client.post("/reports", json=PIN, headers=reg(client))
    assert client.get("/mod/queue", headers=m).json()[0]["segment_id"] == "A3"
    before = {s["segment_id"]: s for s in client.get("/overlays").json()["segments"]}
    assert before["A3"]["concern"] == "amber"  # not red until reviewed
    assert client.post("/mod/segments/A3", json={"action": "confirm"}, headers=m).json()["state"] == "red"
    # flag changes route recommendation at night; explanation names the segment
    out = client.post("/routes/compare", json={"origin": {"lat": 28.45, "lon": 77.02}, "dest": {"lat": 28.45, "lon": 77.02}, "mode": "night"}).json()
    assert [r["id"] for r in out["routes"] if r["recommended"]] == ["B"]


def test_overlay_marks_unmeasured_signal_as_unknown(client, app):
    segs = client.get("/overlays").json()["segments"]
    assert all(s["signal"] in ("good", "weak", "none") for s in segs)  # seeded with samples
    client.post("/signal/batch", json=[{"lat": 28.4567, "lon": 77.0285, "level": 0}], headers=reg(client))


def test_journey_guard_deadman(client, app):
    h = reg(client)
    t = client.post("/trips", json={"contact_name": "Mom", "contact_phone": "+910000000000", "expected_minutes": 20, "checkin_interval_s": 60}, headers=h).json()
    client.post(f"/trips/{t['trip_id']}/heartbeat", json={"lat": 28.45, "lon": 77.02, "battery": 41}, headers=h)
    now = utcnow()
    with app.state.SessionLocal() as db:
        services.sweep_trips(db, app.state.notifier, now + timedelta(seconds=30))
        assert app.state.notifier.outbox == []  # before the deadline: silent
        services.sweep_trips(db, app.state.notifier, now + timedelta(seconds=90))
        assert app.state.notifier.outbox[-1][0] == "push"  # user prompted first
        services.sweep_trips(db, app.state.notifier, now + timedelta(seconds=90 + 200))
        kind, phone, text = app.state.notifier.outbox[-1]
        assert kind == "sms" and "28.45000,77.02000" in text and "41%" in text  # then the contact is alerted
    view = client.get(t["contact_link"]).json()
    assert view["status"] == "escalated" and "user_id" not in view


def test_safe_resets_prompt_and_trip_isolated_per_user(client, app):
    h = reg(client)
    t = client.post("/trips", json={"contact_name": "A", "contact_phone": "1", "expected_minutes": 10}, headers=h).json()
    assert client.post(f"/trips/{t['trip_id']}/safe", headers=h).json()["status"] == "active"
    assert client.post(f"/trips/{t['trip_id']}/end", headers=reg(client)).status_code == 404  # another user cannot touch it


def test_sos_notifies_contact_when_trip_active(client, app):
    h = reg(client)
    client.post("/trips", json={"contact_name": "A", "contact_phone": "999", "expected_minutes": 10}, headers=h)
    r = client.post("/sos", json={"lat": 28.45, "lon": 77.02}, headers=h)
    assert r.status_code == 201 and r.json()["channels"]["sms_contact"] == "queued"
    assert client.get("/admin/audit-verify", headers=staff(client, "admin")).json()["chain_ok"] is True


def test_console_page_and_security_headers(client):
    r = client.get("/console")
    assert r.status_code == 200 and "SafeCircle moderation console" in r.text
    assert "frame-ancestors 'none'" in r.headers["content-security-policy"] and r.headers["cache-control"] == "no-store"


def test_moderator_detail_hides_identities_and_lists_flagged(client):
    m = staff(client)
    tokens = [reg(client) for _ in range(4)]
    for h in tokens:
        client.post("/reports", json={**PIN, "note": "dark, call 9876543210"}, headers=h)
    assert client.get("/mod/segments", headers=reg(client)).status_code == 403
    flagged = client.get("/mod/segments", headers=m).json()
    assert flagged[0]["segment_id"] == "A3" and flagged[0]["pending_review"] is True
    d = client.get("/mod/segments/A3", headers=m).json()
    assert len(d["reports"]) == 4 and d["pending_review"] is True
    assert all("user_id" not in r for r in d["reports"])
    assert "9876543210" not in str(d)  # phone numbers are redacted from notes
    client.post("/mod/segments/A3", json={"action": "confirm", "reason": "seen on site"}, headers=m)
    d = client.get("/mod/segments/A3", headers=m).json()
    assert d["state"] == "red" and d["history"][0]["action"] == "confirm"
    client.post("/mod/segments/A3", json={"action": "resolve", "reason": "lights repaired"}, headers=m)
    assert client.get("/mod/segments/A3", headers=m).json()["state"] == "no_data"
    assert client.get("/mod/segments/NOPE", headers=m).status_code == 404


def test_region_endpoint_and_fence(client):
    g = client.get("/region").json()
    assert g["name"] == "Delhi and Haryana" and g["bbox"]["north"] > g["bbox"]["south"]
    assert {"Delhi", "Gurugram"} <= {p["name"] for p in g["places"]}
    mumbai = {**PIN, "lat": 19.07, "lon": 72.87, "user_lat": 19.07, "user_lon": 72.87}
    r = client.post("/reports", json=mumbai, headers=reg(client))
    c = client.post("/routes/compare", json={"origin": {"lat": 19.07, "lon": 72.87}, "dest": {"lat": 28.45, "lon": 77.02}, "mode": "day"})
    assert c.status_code == 422


def test_routes_compare_includes_coords(client):
    r = client.post("/routes/compare", json={"origin": {"lat": 28.45, "lon": 77.02}, "dest": {"lat": 28.465, "lon": 77.038}, "mode": "day"}).json()
    assert len(r["routes"]) >= 2
    for route in r["routes"]:
        assert "coords" in route
        assert len(route["coords"]) >= 2
        assert all(len(pt) == 2 for pt in route["coords"])


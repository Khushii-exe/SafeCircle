import hashlib, re, secrets, uuid
from datetime import timedelta

from fastapi import HTTPException
from sqlalchemy import func, select

from . import scoring
from .config import settings as cfg
from .geo import haversine_m, snap
from .region import PILOT, in_region
from .models import AuditLog, ModAction, Report, Segment, SegmentState, SignalSample, SosEvent, Trip, utcnow
from .seed import DEMO_ROUTES

CATEGORIES = ["poor_lighting", "isolated", "harassment", "no_people", "blocked_path", "other"]


class Notifier:
    """Stub: collects messages. Replace with FCM / SMS (DLT-registered templates) in production."""
    def __init__(self):
        self.outbox = []

    def push_user(self, user_id, text):
        self.outbox.append(("push", user_id, text))

    def sms(self, phone, text):
        self.outbox.append(("sms", phone, text))


# ---------- audit ----------
def audit(db, actor, action, obj, detail="", now=None):
    last = db.scalars(select(AuditLog).order_by(AuditLog.id.desc()).limit(1)).first()
    prev, ts = (last.hash if last else ""), (now or utcnow())
    h = hashlib.sha256(f"{prev}|{actor}|{action}|{obj}|{detail}|{ts.isoformat()}".encode()).hexdigest()
    db.add(AuditLog(actor=actor, action=action, obj=obj, detail=detail, ts=ts, prev_hash=prev, hash=h))
    db.flush()


def verify_audit_chain(db):
    prev = ""
    for r in db.scalars(select(AuditLog).order_by(AuditLog.id)):
        h = hashlib.sha256(f"{prev}|{r.actor}|{r.action}|{r.obj}|{r.detail}|{r.ts.isoformat()}".encode()).hexdigest()
        if r.prev_hash != prev or r.hash != h:
            return False
        prev = r.hash
    return True


# ---------- reports and moderation ----------
def recompute_segment(db, seg_id, now=None):
    now = now or utcnow()
    reps = db.scalars(select(Report).where(Report.segment_id == seg_id, Report.duplicate.is_(False), Report.dismissed.is_(False))).all()
    score = scoring.concern_score(((now - r.created_at).total_seconds() / 86400, r.weight) for r in reps)
    users = len({r.user_id for r in reps if (now - r.created_at).days <= 90})
    st = db.get(SegmentState, seg_id)
    if st is None:
        st = SegmentState(segment_id=seg_id, mod_confirmed=False)
        db.add(st)
    if score < cfg.red_at:
        st.mod_confirmed = False  # red lapses with decay; a new red needs a new review
    st.score, st.distinct_users, st.updated_at = score, users, now
    st.state = scoring.decide_state(score, users, st.mod_confirmed)
    db.flush()
    return st


def add_report(db, uid, category, time_bucket, note, lat, lon, user_pos=None, now=None):
    now = now or utcnow()
    if not in_region(lat, lon):
        raise HTTPException(422, f"SafeCircle currently covers {PILOT['name']} only.")
    seg, _ = snap((lat, lon), db.scalars(select(Segment)).all(), cfg.snap_radius_m)
    if seg is None:
        raise HTTPException(422, "No road within 30 m of the pin. Move the pin onto a road.")
    count = db.scalar(select(func.count()).select_from(Report).where(Report.user_id == uid, Report.created_at >= now - timedelta(days=1)))
    if count >= cfg.max_reports_per_day:
        raise HTTPException(429, "Daily report limit reached.")
    dup = db.scalar(select(func.count()).select_from(Report).where(
        Report.user_id == uid, Report.segment_id == seg.id, Report.category == category,
        Report.duplicate.is_(False), Report.created_at >= now - timedelta(hours=cfg.dup_window_h))) > 0
    verified = user_pos is not None and haversine_m(user_pos, (lat, lon)) <= cfg.presence_radius_m
    note = re.sub(r"\+?\d[\d\s-]{8,}\d", "[number removed]", note or "")[:140]
    r = Report(user_id=uid, segment_id=seg.id, category=category, time_bucket=time_bucket, note=note,
               weight=1.0 if verified else cfg.unverified_weight, duplicate=dup, created_at=now)
    db.add(r)
    db.flush()
    st = recompute_segment(db, seg.id, now)
    db.commit()
    return {"report_id": r.id, "segment_id": seg.id, "counted": not dup, "verified_presence": verified,
            "segment_state": st.state, "pending_review": scoring.needs_review(st.score, st.distinct_users, st.mod_confirmed)}


def moderate(db, mod_id, seg_id, action, reason="", now=None):
    now = now or utcnow()
    st = db.get(SegmentState, seg_id)
    if st is None:
        raise HTTPException(404, "Segment has no reports.")
    if action == "confirm":
        if not scoring.needs_review(st.score, st.distinct_users, st.mod_confirmed):
            raise HTTPException(409, "Segment does not meet the evidence rules for red (score and 3+ distinct users).")
        st.mod_confirmed = True
    else:  # dismiss | resolve: remove the evidence from scoring (kept in DB for audit)
        for r in db.scalars(select(Report).where(Report.segment_id == seg_id)):
            r.dismissed = True
    db.add(ModAction(segment_id=seg_id, moderator_id=mod_id, action=action, reason=reason[:200], created_at=now))
    st = recompute_segment(db, seg_id, now)
    audit(db, mod_id, f"moderation_{action}", seg_id, reason[:200], now)
    db.commit()
    return st


def review_queue(db):
    out = []
    for st in db.scalars(select(SegmentState)):
        if scoring.needs_review(st.score, st.distinct_users, st.mod_confirmed):
            seg = db.get(Segment, st.segment_id)
            cats = db.execute(select(Report.category, func.count()).where(Report.segment_id == st.segment_id, Report.duplicate.is_(False), Report.dismissed.is_(False)).group_by(Report.category)).all()
            out.append({"segment_id": st.segment_id, "name": seg.name if seg else "", "score": round(st.score, 2),
                        "distinct_users": st.distinct_users, "categories": {c: n for c, n in cats}})
    return out  # no user identities exposed to moderators


def flagged_segments(db):
    """Everything currently amber/red or awaiting review, for the moderator list."""
    out = []
    for st in db.scalars(select(SegmentState).order_by(SegmentState.score.desc())):
        pending = scoring.needs_review(st.score, st.distinct_users, st.mod_confirmed)
        if st.state != "no_data" or pending:
            seg = db.get(Segment, st.segment_id)
            out.append({"segment_id": st.segment_id, "name": seg.name if seg else "", "state": st.state, "score": round(st.score, 2),
                        "distinct_users": st.distinct_users, "pending_review": pending})
    return out


def segment_detail(db, seg_id, now=None):
    """Moderator view: report contents and history, never user identities."""
    now = now or utcnow()
    st, seg = db.get(SegmentState, seg_id), db.get(Segment, seg_id)
    if seg is None:
        raise HTTPException(404, "Unknown segment.")
    reps = db.scalars(select(Report).where(Report.segment_id == seg_id).order_by(Report.created_at.desc()).limit(100)).all()
    acts = db.scalars(select(ModAction).where(ModAction.segment_id == seg_id).order_by(ModAction.created_at.desc()).limit(20)).all()
    return {"segment_id": seg_id, "name": seg.name,
            "state": st.state if st else "no_data", "score": round(st.score, 2) if st else 0.0,
            "distinct_users": st.distinct_users if st else 0,
            "pending_review": bool(st) and scoring.needs_review(st.score, st.distinct_users, st.mod_confirmed),
            "reports": [{"category": r.category, "time_bucket": r.time_bucket, "age_days": round((now - r.created_at).total_seconds() / 86400, 1),
                         "weight": r.weight, "counted": not (r.duplicate or r.dismissed), "note": r.note} for r in reps],
            "history": [{"action": a.action, "reason": a.reason, "at": a.created_at.isoformat()} for a in acts]}


# ---------- signal ----------
def add_signal(db, samples, now=None):
    now = now or utcnow()
    segs = db.scalars(select(Segment)).all()
    ok = 0
    for s in samples:
        seg, _ = snap((s["lat"], s["lon"]), segs, cfg.snap_radius_m)
        if seg:
            db.add(SignalSample(segment_id=seg.id, carrier=s.get("carrier", "unknown"), level=s["level"], ts=now))
            ok += 1
    db.commit()
    return {"accepted": ok, "rejected": len(samples) - ok}


def signal_n(db, seg_id):
    rows = db.execute(select(SignalSample.carrier, SignalSample.level).where(SignalSample.segment_id == seg_id)).all()
    if len(rows) < cfg.min_signal_samples:
        return None, len(rows)
    by = {}
    for c, lv in rows:
        by.setdefault(c, []).append(lv)
    level = min(sorted(v)[len(v) // 2] for v in by.values())  # worst carrier median
    return scoring.n_from_level(level), len(rows)


# ---------- overlays ----------
def overlays(db):
    out = []
    for seg in db.scalars(select(Segment)):
        st = db.get(SegmentState, seg.id)
        n, cnt = signal_n(db, seg.id)
        # Count and timestamp of non-duplicate, non-dismissed reports for provenance display
        rep_count = db.scalar(select(func.count()).select_from(Report).where(
            Report.segment_id == seg.id, Report.duplicate.is_(False), Report.dismissed.is_(False))) or 0
        last_rep = db.scalar(select(func.max(Report.created_at)).where(
            Report.segment_id == seg.id, Report.duplicate.is_(False), Report.dismissed.is_(False)))
        out.append({"segment_id": seg.id, "name": seg.name, "geom": seg.geom,
                    "concern": st.state if st else "no_data",
                    "signal": None if n is None else ("good" if n <= cfg.n_values["good"] else "weak" if n <= cfg.n_values["weak"] else "none"),
                    "signal_samples": cnt,
                    "report_count": rep_count,
                    "last_report_at": last_rep.isoformat() if last_rep else None})
    return out


# ---------- route comparison ----------
def segment_inputs(db, seg, length_m=None):
    st = db.get(SegmentState, seg.id)
    state = st.state if st else "no_data"
    n, _ = signal_n(db, seg.id)
    return {"id": seg.id, "name": seg.name, "length_m": length_m or seg.length_m, "S": cfg.s_values[state], "state": state,
            "N": cfg.n_unknown if n is None else n, "N_measured": n is not None,
            "I": cfg.i_unknown if seg.isolation is None else seg.isolation}


def _route_coords(seg_ids, segs):
    coords = []
    for sid in seg_ids:
        if sid in segs and segs[sid].geom:
            for pt in segs[sid].geom:
                if not coords or coords[-1] != pt:
                    coords.append(pt)
    return coords


def candidate_routes(db, origin, dest):
    segs = {s.id: s for s in db.scalars(select(Segment))}
    if not cfg.osrm_url:  # demo mode: seeded synthetic routes
        return [{
            "id": r["id"],
            "name": r["name"],
            "minutes": r["minutes"],
            "km": r["km"],
            "coords": _route_coords(r["segments"], segs),
            "parts": [segment_inputs(db, segs[i]) for i in r["segments"] if i in segs]
        } for r in DEMO_ROUTES], "demo"
    from .routing import map_to_segments, osrm_routes
    out = []
    for i, x in enumerate(osrm_routes(cfg.osrm_url, origin, dest)):
        used, unmapped = map_to_segments(x["coords"], list(segs.values()))
        parts = [segment_inputs(db, s, m) for s, m in used]
        if unmapped:
            parts.append({"id": "unmapped", "name": "Unmapped road", "length_m": unmapped, "S": cfg.s_values["no_data"], "state": "no_data",
                          "N": cfg.n_unknown, "N_measured": False, "I": cfg.i_unknown})
        out.append({"id": f"R{i + 1}", "name": f"Route {chr(65 + i)}", "minutes": x["minutes"], "km": x["km"], "coords": x["coords"], "parts": parts})
    return out, "osrm"


def explain(best, fastest, mode):
    if best is fastest:
        return f"{best['name']} is both the quickest and the lowest-scoring option for {mode} travel."
    have = {p["id"] for p in best["_parts"]}
    reds = [p["name"] for p in fastest["_parts"] if p["state"] == "red" and p["id"] not in have]
    weak = sum(p["length_m"] for p in fastest["_parts"] if p["N_measured"] and p["N"] >= cfg.n_values["weak"] and p["id"] not in have)
    bits = []
    if reds:
        bits.append("avoids a reviewed red segment (" + ", ".join(reds) + ")")
    if weak >= 100:
        bits.append(f"avoids about {int(round(weak / 50) * 50)} m of weak mobile signal")
    extra = f"adds {round(best['minutes'] - fastest['minutes'])} min and {best['km'] - fastest['km']:.1f} km"
    tail = (" but " + " and ".join(bits)) if bits else "; it scores lower on concern, signal and isolation combined"
    return f"{best['name']} {extra}{tail}. You can still choose either route."


def compare_routes(db, origin, dest, mode):
    routes, source = candidate_routes(db, origin, dest)
    tmin = min(r["minutes"] for r in routes)
    for r in routes:
        sc = scoring.route_score(r["parts"], mode, r["minutes"], tmin)
        w, total = sc["weights"], sum(p["length_m"] for p in r["parts"]) or 1.0
        contrib = lambda p: (p["length_m"] / total) * (w["S"] * p["S"] + w["N"] * p["N"] + w["I"] * p["I"])
        r.update(score=round(sc["R"], 3), terms={k: round(sc[k], 3) for k in "SNID"}, _parts=r["parts"],
                 unmeasured_signal_fraction=round(sum(p["length_m"] for p in r["parts"] if not p["N_measured"]) / total, 2),
                 worst_segments=[{"id": p["id"], "name": p["name"], "concern": p["state"], "signal_measured": p["N_measured"]}
                                 for p in sorted(r["parts"], key=contrib, reverse=True)[:3]])
        del r["parts"]
        r["recommended"] = False
    best = min(routes, key=lambda r: (r["score"], r["minutes"]))
    best["recommended"] = True
    fastest = min(routes, key=lambda r: r["minutes"])
    text = explain(best, fastest, mode)
    for r in routes:
        r.pop("_parts")
    return {"mode": mode, "source": source, "routes": routes, "explanation": text,
            "disclaimer": "Supports informed decisions, not a guarantee of safety. 'No data' means unknown, never safe."}


# ---------- journey guard ----------
def start_trip(db, uid, contact_name, contact_phone, minutes, interval_s, now=None):
    now = now or utcnow()
    t = Trip(id=str(uuid.uuid4()), user_id=uid, contact_name=contact_name, contact_phone=contact_phone, link_token=secrets.token_urlsafe(24),
             checkin_interval_s=interval_s, expected_arrival=now + timedelta(minutes=minutes), next_deadline=now + timedelta(seconds=interval_s))
    db.add(t)
    audit(db, uid, "trip_start", t.id, now=now)
    db.commit()
    return t


def sweep_trips(db, notifier, now=None):
    """Server-side dead-man timer: runs every ~30 s in a worker. Prompt the user first, then alert the trusted contact."""
    now = now or utcnow()
    for t in db.scalars(select(Trip).where(Trip.status.in_(["active", "prompted"]))):
        if t.status == "active" and now > t.next_deadline:
            t.status, t.prompted_at = "prompted", now
            notifier.push_user(t.user_id, "Are you OK? Tap 'I'm safe' to confirm.")
        elif t.status == "prompted" and now > t.prompted_at + timedelta(seconds=cfg.checkin_grace_s):
            t.status = "escalated"
            where = f"{t.last_lat:.5f},{t.last_lon:.5f} at {t.last_ts:%H:%M} UTC" if t.last_lat is not None else "unknown"
            batt = f", battery {t.battery}%" if t.battery is not None else ""
            notifier.sms(t.contact_phone, f"SafeCircle: a check-in was missed. Last known location: {where}{batt}. Live link: /t/{t.link_token}")
            audit(db, "system", "trip_escalated", t.id, now=now)
    db.commit()


def trip_for(db, uid, trip_id):
    t = db.get(Trip, trip_id)
    if t is None or t.user_id != uid:
        raise HTTPException(404, "Trip not found.")
    return t


def sos(db, uid, lat, lon, note, notifier, now=None):
    now = now or utcnow()
    trip = db.scalars(select(Trip).where(Trip.user_id == uid, Trip.status.in_(["active", "prompted", "escalated"]))).first()
    ev = SosEvent(user_id=uid, lat=lat, lon=lon, note=(note or "")[:140], created_at=now, channels={"server": "received"})
    if trip:
        notifier.sms(trip.contact_phone, f"SafeCircle SOS: location {lat:.5f},{lon:.5f} at {now:%H:%M} UTC. Live link: /t/{trip.link_token}")
        ev.channels = {"server": "received", "sms_contact": "queued"}
    db.add(ev)
    audit(db, uid, "sos", str(lat) + "," + str(lon), now=now)
    db.commit()
    return {"sos_id": ev.id, "channels": ev.channels, "note": "Delivery is not guaranteed; also call 112."}

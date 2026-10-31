"""Synthetic demo data that reproduces the slide-12 calculation. All values are invented and illustrative."""
from datetime import timedelta

from .models import Report, Segment, SignalSample, User, utcnow

A_PTS = [(28.4500, 77.0200), (28.4520, 77.0235), (28.4550, 77.0270), (28.4585, 77.0300), (28.4620, 77.0340), (28.4650, 77.0380)]
B_PTS = [(28.4500, 77.0200), (28.4480, 77.0245), (28.4490, 77.0295), (28.4520, 77.0335), (28.4570, 77.0360), (28.4615, 77.0375), (28.4650, 77.0380)]
# id, length_m, isolation baseline, signal bars (0-4)
A_SEGS = [("A1", 600, 0.4, 4), ("A2", 600, 0.4, 4), ("A3", 800, 0.7, 0), ("A4", 600, 0.4, 4), ("A5", 600, 0.4, 1)]
B_SEGS = [("B1", 600, 0.30, 4), ("B2", 700, 0.30, 4), ("B3", 800, 0.30, 1), ("B4", 600, 0.30, 4), ("B5", 600, 0.30, 4), ("B6", 600, 0.25, 4)]
DEMO_ROUTES = [
    {"id": "A", "name": "Route A", "minutes": 14.0, "km": 3.2, "segments": [s[0] for s in A_SEGS]},
    {"id": "B", "name": "Route B", "minutes": 18.0, "km": 3.9, "segments": [s[0] for s in B_SEGS]},
]


def seed_demo(db, now=None):
    now = now or utcnow()
    if db.get(Segment, "A1"):
        return
    db.add(User(id="demo-user", role="user"))
    for pts, segs in ((A_PTS, A_SEGS), (B_PTS, B_SEGS)):
        for i, (sid, length, iso, bars) in enumerate(segs):
            geom = [list(pts[i]), list(pts[i + 1])]
            db.add(Segment(id=sid, name=f"{sid} (demo road)", length_m=length, geom=geom, isolation=iso))
            for _ in range(3):
                db.add(SignalSample(segment_id=sid, carrier="demo", level=bars, ts=now))
    db.flush()
    # one amber segment on B (poor lighting) so S differs between routes, as on slide 12
    from .services import recompute_segment
    db.add(Report(user_id="demo-user", segment_id="B2", category="poor_lighting", time_bucket="night", weight=1.0, created_at=now))
    db.flush()
    recompute_segment(db, "B2", now)
    db.commit()

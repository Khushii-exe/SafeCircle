"""Reproduces slide 21 (decay table) and slide 12 (route scores) of the Screen-1 deck."""
from datetime import timedelta

import pytest

from app import services
from app.models import utcnow
from app.scoring import concern_score, decide_state


def test_decay_table_slide_21():
    # (day, events as (day_of_report, weight)) -> expected score
    reports = [0, 2, 5, 6]
    expect = {0: 1.00, 2: 1.95, 5: 2.82, 6: 3.76}
    for day, want in expect.items():
        items = [(day - d, 1.0) for d in reports if d <= day]
        assert concern_score(items) == pytest.approx(want, abs=0.01)
    assert concern_score([(66 - d, 1.0) for d in reports]) == pytest.approx(0.94, abs=0.01)  # amber
    assert concern_score([(96 - d, 1.0) for d in reports]) == pytest.approx(0.47, abs=0.01)  # no data


def test_state_rules():
    assert decide_state(0.47, 4, True) == "no_data"
    assert decide_state(0.94, 4, True) == "amber"
    assert decide_state(3.76, 4, False) == "amber"  # needs moderator
    assert decide_state(3.76, 2, True) == "amber"   # needs 3+ users
    assert decide_state(3.76, 4, True) == "red"


def _r(db, mode):
    out = services.compare_routes(db, (0, 0), (0, 0), mode)
    return {r["id"]: r for r in out["routes"]}, out


def test_slide_12_no_flag(db):
    day, _ = _r(db, "day")
    assert day["A"]["score"] == pytest.approx(0.236, abs=0.002) and day["A"]["recommended"]
    assert day["B"]["score"] == pytest.approx(0.284, abs=0.002)
    night, out = _r(db, "night")
    assert night["A"]["score"] == pytest.approx(0.324, abs=0.002)
    assert night["B"]["score"] == pytest.approx(0.288, abs=0.002) and night["B"]["recommended"]
    assert "adds" not in out["explanation"] or "Route B" in out["explanation"]


def test_flagging_a3_changes_scores(db):
    now = utcnow()
    for i in range(4):  # 4 distinct users report segment A3 (midpoint of its geometry)
        services.add_report(db, f"u{i}", "poor_lighting", "night", "", 28.4567, 77.0285, (28.4567, 77.0285), now)
    q = services.review_queue(db)
    assert q and q[0]["segment_id"] == "A3" and q[0]["distinct_users"] == 4
    services.moderate(db, "mod1", "A3", "confirm", "reviewed on site")
    day, _ = _r(db, "day")
    assert day["A"]["score"] == pytest.approx(0.281, abs=0.002) and day["A"]["recommended"]  # lead nearly erased (gap 0.003)
    night, out = _r(db, "night")
    assert night["A"]["score"] == pytest.approx(0.391, abs=0.002) and night["B"]["recommended"]
    assert "red segment" in out["explanation"] and "A3" in out["explanation"]
    assert services.verify_audit_chain(db)

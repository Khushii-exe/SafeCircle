"""Pure scoring logic: evidence decay, state rules, route score R = wS*S + wN*N + wI*I + wD*D (lower is better)."""
from .config import settings as cfg


def decay_weight(age_days, half_life=None):
    return 0.5 ** (max(age_days, 0.0) / (half_life or cfg.half_life_days))


def concern_score(items, half_life=None):
    """items: iterable of (age_days, weight). Each counted report decays with a 30-day half-life."""
    return sum(w * decay_weight(a, half_life) for a, w in items)


def decide_state(score, users, confirmed):
    if score >= cfg.red_at and users >= cfg.red_min_users and confirmed:
        return "red"
    if score >= cfg.amber_at:
        return "amber"
    return "no_data"  # unknown, never 'safe'


def needs_review(score, users, confirmed):
    return score >= cfg.red_at and users >= cfg.red_min_users and not confirmed


def n_from_level(level):
    """Signal bars 0-4 -> signal risk. 3-4 good, 1-2 weak, 0 none."""
    return cfg.n_values["good"] if level >= 3 else cfg.n_values["weak"] if level >= 1 else cfg.n_values["none"]


def route_score(parts, mode, minutes, min_minutes):
    """parts: dicts with length_m, S, N, I. S, N, I are length-weighted averages; D = (t - tmin) / tmin, capped at 1."""
    w = cfg.weights[mode]
    total = sum(p["length_m"] for p in parts) or 1.0
    avg = lambda k: sum(p["length_m"] * p[k] for p in parts) / total
    S, N, I = avg("S"), avg("N"), avg("I")
    D = min(1.0, max(0.0, (minutes - min_minutes) / min_minutes)) if min_minutes else 0.0
    R = w["S"] * S + w["N"] * N + w["I"] * I + w["D"] * D
    return {"R": R, "S": S, "N": N, "I": I, "D": D, "weights": w}

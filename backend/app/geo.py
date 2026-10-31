import math

EARTH_R = 6371000.0


def haversine_m(a, b):
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * EARTH_R * math.asin(math.sqrt(h))


def _xy(p, ref):
    return ((p[1] - ref[1]) * math.cos(math.radians(ref[0])) * 111320.0, (p[0] - ref[0]) * 110540.0)


def point_segment_m(p, a, b):
    px, py = _xy(p, a)
    bx, by = _xy(b, a)
    L2 = bx * bx + by * by
    t = 0.0 if L2 == 0 else max(0.0, min(1.0, (px * bx + py * by) / L2))
    return math.hypot(px - t * bx, py - t * by)


def distance_to_polyline_m(p, line):
    return min(point_segment_m(p, a, b) for a, b in zip(line, line[1:]))


def snap(p, segments, max_m):
    """Nearest segment within max_m metres, else (None, None). Linear scan is fine at pilot scale; PostGIS KNN replaces it in production."""
    best, best_d = None, None
    for s in segments:
        d = distance_to_polyline_m(p, s.geom)
        if d <= max_m and (best_d is None or d < best_d):
            best, best_d = s, d
    return best, best_d

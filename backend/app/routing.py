"""OSRM client + mapping of a route polyline onto road segments (used when OSRM_URL is set)."""
import httpx

from .geo import haversine_m, snap


def osrm_routes(base_url, origin, dest):
    """origin/dest are (lat, lon). Uses the foot profile; build OSRM with a foot profile for walking routes."""
    r = httpx.get(
        f"{base_url}/route/v1/foot/{origin[1]},{origin[0]};{dest[1]},{dest[0]}",
        params={"alternatives": "3", "geometries": "geojson", "overview": "full"},
        timeout=10,
    )
    r.raise_for_status()
    return [
        {"minutes": x["duration"] / 60.0, "km": x["distance"] / 1000.0, "coords": [(c[1], c[0]) for c in x["geometry"]["coordinates"]]}
        for x in r.json()["routes"]
    ]


def map_to_segments(coords, segments, radius_m=40.0):
    """Returns ({segment_id: metres travelled}, unmapped_metres). Unmapped stretches get neutral, flagged defaults."""
    used, unmapped = {}, 0.0
    by_id = {}
    for a, b in zip(coords, coords[1:]):
        length = haversine_m(a, b)
        seg, _ = snap(((a[0] + b[0]) / 2, (a[1] + b[1]) / 2), segments, radius_m)
        if seg:
            used[seg.id] = used.get(seg.id, 0.0) + length
            by_id[seg.id] = seg
        else:
            unmapped += length
    return [(by_id[i], m) for i, m in used.items()], unmapped

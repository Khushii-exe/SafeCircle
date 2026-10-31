"""Pilot region: Delhi and Haryana. The bounding box is a coarse fence (it also clips parts of neighbouring states).
Replace it with the exact state-boundary polygon when PostGIS is added (ST_Contains)."""

PILOT = {
    "name": "Delhi and Haryana",
    "bbox": {"south": 27.60, "west": 74.40, "north": 30.95, "east": 77.65},
    "center": {"lat": 28.50, "lon": 77.05},  # Delhi NCR / Gurugram
    "zoom": 10,
    "min_zoom": 7,
    # approximate city centres for quick-jump buttons
    "places": [
        {"name": "Gurugram", "lat": 28.4595, "lon": 77.0266},
        {"name": "Delhi", "lat": 28.6139, "lon": 77.2090},
        {"name": "Faridabad", "lat": 28.4089, "lon": 77.3178},
        {"name": "Farukhnagar", "lat": 28.47, "lon": 76.82},
        {"name": "Sonipat", "lat": 28.9931, "lon": 77.0151},
        {"name": "Rohtak", "lat": 28.8955, "lon": 76.6066},
        {"name": "Panipat", "lat": 29.3909, "lon": 76.9635},
        {"name": "Karnal", "lat": 29.6857, "lon": 76.9905},
        {"name": "Ambala", "lat": 30.3782, "lon": 76.7767},
        {"name": "Hisar", "lat": 29.1492, "lon": 75.7217},
    ],
}


def in_region(lat: float, lon: float) -> bool:
    b = PILOT["bbox"]
    return b["south"] <= lat <= b["north"] and b["west"] <= lon <= b["east"]

"""All thresholds and weights are configurable (slides 6, 21). Values are team choices to tune on pilot data."""
import os
from dataclasses import dataclass, field


def _default_db_url() -> str:
    if os.getenv("DATABASE_URL"):
        return os.environ["DATABASE_URL"]
    if os.getenv("VERCEL"):
        return "sqlite:////tmp/safecircle.db"
    return "sqlite:///./safecircle.db"


@dataclass
class Settings:
    database_url: str = field(default_factory=_default_db_url)
    secret_key: str = field(default_factory=lambda: os.getenv("SECRET_KEY", "dev-secret-change-me"))
    admin_key: str = field(default_factory=lambda: os.getenv("ADMIN_KEY", "dev-admin-key"))
    osrm_url: str = field(default_factory=lambda: os.getenv("OSRM_URL", ""))  # e.g. http://osrm:5000 ; empty = demo routes
    # report evidence rules
    half_life_days: float = 30.0
    amber_at: float = 0.8
    red_at: float = 2.5
    red_min_users: int = 3
    dup_window_h: float = 24.0
    max_reports_per_day: int = 5
    presence_radius_m: float = 150.0
    unverified_weight: float = 0.5
    snap_radius_m: float = 30.0
    # scoring
    s_values: dict = field(default_factory=lambda: {"no_data": 0.30, "amber": 0.55, "red": 0.90})
    n_values: dict = field(default_factory=lambda: {"good": 0.10, "weak": 0.50, "none": 0.90})
    n_unknown: float = 0.50  # unmeasured signal: neutral and flagged as unmeasured, never treated as good
    i_unknown: float = 0.50
    min_signal_samples: int = 3
    weights: dict = field(default_factory=lambda: {
        "day": {"S": 0.30, "N": 0.20, "I": 0.15, "D": 0.35},
        "night": {"S": 0.45, "N": 0.25, "I": 0.20, "D": 0.10},
    })
    # journey guard
    checkin_grace_s: int = 180


settings = Settings()

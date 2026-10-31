from datetime import datetime, timezone

from sqlalchemy import JSON, Boolean, DateTime, Float, Integer, String, Text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


def utcnow():
    return datetime.now(timezone.utc).replace(tzinfo=None)


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    role: Mapped[str] = mapped_column(String(16), default="user")  # user | moderator | admin
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class Segment(Base):
    __tablename__ = "segments"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(120), default="")
    length_m: Mapped[float] = mapped_column(Float)
    geom: Mapped[list] = mapped_column(JSON)  # [[lat, lon], ...]
    isolation: Mapped[float | None] = mapped_column(Float, nullable=True)  # 0-1 baseline from OSM tags; None = unknown


class Report(Base):
    __tablename__ = "reports"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(String(36), index=True)
    segment_id: Mapped[str] = mapped_column(String(64), index=True)
    category: Mapped[str] = mapped_column(String(24))
    time_bucket: Mapped[str] = mapped_column(String(8), default="night")
    note: Mapped[str] = mapped_column(String(160), default="")
    weight: Mapped[float] = mapped_column(Float, default=1.0)
    duplicate: Mapped[bool] = mapped_column(Boolean, default=False)
    dismissed: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)


class SegmentState(Base):
    __tablename__ = "segment_state"
    segment_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    score: Mapped[float] = mapped_column(Float, default=0.0)
    distinct_users: Mapped[int] = mapped_column(Integer, default=0)
    mod_confirmed: Mapped[bool] = mapped_column(Boolean, default=False)
    state: Mapped[str] = mapped_column(String(10), default="no_data")
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class ModAction(Base):
    __tablename__ = "moderation_actions"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    segment_id: Mapped[str] = mapped_column(String(64))
    moderator_id: Mapped[str] = mapped_column(String(36))
    action: Mapped[str] = mapped_column(String(16))  # confirm | dismiss | resolve
    reason: Mapped[str] = mapped_column(String(200), default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class SignalSample(Base):
    __tablename__ = "signal_samples"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    segment_id: Mapped[str] = mapped_column(String(64), index=True)
    carrier: Mapped[str] = mapped_column(String(24), default="unknown")
    level: Mapped[int] = mapped_column(Integer)  # 0-4 bars
    ts: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class Trip(Base):
    __tablename__ = "trips"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    user_id: Mapped[str] = mapped_column(String(36), index=True)
    contact_name: Mapped[str] = mapped_column(String(80))
    contact_phone: Mapped[str] = mapped_column(String(20))
    link_token: Mapped[str] = mapped_column(String(64), unique=True)
    checkin_interval_s: Mapped[int] = mapped_column(Integer, default=300)
    expected_arrival: Mapped[datetime] = mapped_column(DateTime)
    next_deadline: Mapped[datetime] = mapped_column(DateTime)
    status: Mapped[str] = mapped_column(String(12), default="active")  # active|prompted|escalated|ended
    prompted_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    last_lat: Mapped[float | None] = mapped_column(Float, nullable=True)
    last_lon: Mapped[float | None] = mapped_column(Float, nullable=True)
    last_ts: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    battery: Mapped[int | None] = mapped_column(Integer, nullable=True)


class SosEvent(Base):
    __tablename__ = "sos_events"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(String(36))
    lat: Mapped[float] = mapped_column(Float)
    lon: Mapped[float] = mapped_column(Float)
    note: Mapped[str] = mapped_column(String(160), default="")
    channels: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)


class AuditLog(Base):
    """Append-only and hash-chained: each row's hash covers the previous row's hash."""
    __tablename__ = "audit_log"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    actor: Mapped[str] = mapped_column(String(36))
    action: Mapped[str] = mapped_column(String(40))
    obj: Mapped[str] = mapped_column(String(80))
    detail: Mapped[str] = mapped_column(Text, default="")
    ts: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    prev_hash: Mapped[str] = mapped_column(String(64), default="")
    hash: Mapped[str] = mapped_column(String(64), default="")

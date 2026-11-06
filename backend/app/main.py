import asyncio, uuid
from pathlib import Path
from contextlib import asynccontextmanager
from typing import Literal, Optional

from fastapi.responses import HTMLResponse
from fastapi import APIRouter, Depends, FastAPI, Header, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from . import services
from .config import settings
from .region import PILOT, in_region
from .models import Base, Trip, User, utcnow
from .security import make_token, verify_token
from .seed import seed_demo

router = APIRouter()


# ---------- dependencies ----------
def get_db(request: Request):
    with request.app.state.SessionLocal() as db:
        yield db


def current_user(authorization: Optional[str] = Header(None)):
    p = verify_token(authorization[7:]) if authorization and authorization.startswith("Bearer ") else None
    if not p:
        raise HTTPException(401, "Missing or invalid token.")
    return p


def require(*roles):
    def dep(p=Depends(current_user)):
        if p["role"] not in roles:
            raise HTTPException(403, "Not allowed.")
        return p
    return dep


# ---------- schemas ----------
class LatLon(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)


class ReportIn(LatLon):
    category: Literal["poor_lighting", "isolated", "harassment", "no_people", "blocked_path", "other"]
    time_bucket: Literal["day", "night"] = "night"
    note: str = Field("", max_length=160)
    user_lat: Optional[float] = None
    user_lon: Optional[float] = None


class ModIn(BaseModel):
    action: Literal["confirm", "dismiss", "resolve"]
    reason: str = Field("", max_length=200)


class SignalSampleIn(LatLon):
    level: int = Field(ge=0, le=4)
    carrier: str = Field("unknown", max_length=24)


class CompareIn(BaseModel):
    origin: LatLon
    dest: LatLon
    mode: Literal["day", "night"] = "night"


class TripIn(BaseModel):
    contact_name: str = Field(max_length=80)
    contact_phone: str = Field(max_length=20)
    expected_minutes: int = Field(ge=1, le=600)
    checkin_interval_s: int = Field(300, ge=60, le=3600)


class HeartbeatIn(LatLon):
    battery: Optional[int] = Field(None, ge=0, le=100)


class SosIn(LatLon):
    note: str = Field("", max_length=160)


# ---------- auth ----------
@router.post("/auth/register")
def register(db=Depends(get_db)):
    """Dev auth: anonymous pseudonymous user. Production: phone OTP (Firebase Auth) issuing this same token."""
    u = User(id=str(uuid.uuid4()), role="user")
    db.add(u)
    db.commit()
    return {"user_id": u.id, "token": make_token(u.id, "user")}


@router.post("/auth/dev-staff")
def dev_staff(role: Literal["moderator", "admin"], x_admin_key: str = Header(""), db=Depends(get_db)):
    if x_admin_key != settings.admin_key:
        raise HTTPException(403, "Bad admin key.")
    u = User(id=str(uuid.uuid4()), role=role)
    db.add(u)
    db.commit()
    return {"user_id": u.id, "token": make_token(u.id, role)}


# ---------- map layers ----------
@router.get("/overlays")
def get_overlays(db=Depends(get_db)):
    return {"segments": services.overlays(db), "legend": {"concern": "no_data (unknown) | amber | red", "signal": "good | weak | none | null = not measured"}}


# ---------- reports and moderation ----------
@router.post("/reports", status_code=201)
def post_report(body: ReportIn, request: Request, p=Depends(require("user", "moderator", "admin")), db=Depends(get_db)):
    pos = (body.user_lat, body.user_lon) if body.user_lat is not None and body.user_lon is not None else None
    return services.add_report(db, p["uid"], body.category, body.time_bucket, body.note, body.lat, body.lon, pos)


@router.get("/mod/queue")
def mod_queue(p=Depends(require("moderator", "admin")), db=Depends(get_db)):
    return services.review_queue(db)


@router.get("/mod/segments")
def mod_segments(p=Depends(require("moderator", "admin")), db=Depends(get_db)):
    return services.flagged_segments(db)


@router.get("/mod/segments/{segment_id}")
def mod_segment_detail(segment_id: str, p=Depends(require("moderator", "admin")), db=Depends(get_db)):
    return services.segment_detail(db, segment_id)


@router.post("/mod/segments/{segment_id}")
def mod_action(segment_id: str, body: ModIn, p=Depends(require("moderator", "admin")), db=Depends(get_db)):
    st = services.moderate(db, p["uid"], segment_id, body.action, body.reason)
    return {"segment_id": segment_id, "state": st.state, "score": round(st.score, 2)}


# ---------- signal ----------
@router.post("/signal/batch")
def signal_batch(samples: list[SignalSampleIn], p=Depends(current_user), db=Depends(get_db)):
    if len(samples) > 500:
        raise HTTPException(413, "Max 500 samples per batch.")
    return services.add_signal(db, [s.model_dump() for s in samples])


# ---------- routing ----------
@router.get("/region")
def region():
    return PILOT


@router.post("/routes/compare")
def routes_compare(body: CompareIn, db=Depends(get_db)):
    if not (in_region(body.origin.lat, body.origin.lon) and in_region(body.dest.lat, body.dest.lon)):
        raise HTTPException(422, f"SafeCircle currently covers {PILOT['name']} only.")
    return services.compare_routes(db, (body.origin.lat, body.origin.lon), (body.dest.lat, body.dest.lon), body.mode)


# ---------- journey guard ----------
@router.post("/trips", status_code=201)
def trips_create(body: TripIn, p=Depends(current_user), db=Depends(get_db)):
    t = services.start_trip(db, p["uid"], body.contact_name, body.contact_phone, body.expected_minutes, body.checkin_interval_s)
    return {"trip_id": t.id, "contact_link": f"/t/{t.link_token}", "next_deadline": t.next_deadline.isoformat()}


@router.post("/trips/{trip_id}/heartbeat")
def trips_heartbeat(trip_id: str, body: HeartbeatIn, p=Depends(current_user), db=Depends(get_db)):
    t = services.trip_for(db, p["uid"], trip_id)
    t.last_lat, t.last_lon, t.battery, t.last_ts = body.lat, body.lon, body.battery, utcnow()
    db.commit()
    return {"status": t.status}


@router.post("/trips/{trip_id}/safe")
def trips_safe(trip_id: str, extend_s: Optional[int] = None, p=Depends(current_user), db=Depends(get_db)):
    from datetime import timedelta
    t = services.trip_for(db, p["uid"], trip_id)
    t.status, t.prompted_at = "active", None
    t.next_deadline = utcnow() + timedelta(seconds=extend_s or t.checkin_interval_s)
    db.commit()
    return {"status": t.status, "next_deadline": t.next_deadline.isoformat()}


@router.post("/trips/{trip_id}/end")
def trips_end(trip_id: str, p=Depends(current_user), db=Depends(get_db)):
    t = services.trip_for(db, p["uid"], trip_id)
    t.status = "ended"
    db.commit()
    return {"status": t.status}


@router.get("/t/{token}")
def contact_view(token: str, db=Depends(get_db)):
    """Public page for the trusted contact: no account needed, no user identity."""
    t = db.scalars(select(Trip).where(Trip.link_token == token)).first()
    if t is None or t.status == "ended":
        raise HTTPException(404, "Link expired.")
    return {"status": t.status, "last_location": None if t.last_lat is None else {"lat": t.last_lat, "lon": t.last_lon, "at": t.last_ts.isoformat()},
            "battery": t.battery, "expected_arrival": t.expected_arrival.isoformat()}


# ---------- SOS ----------
@router.post("/sos", status_code=201)
def post_sos(body: SosIn, request: Request, p=Depends(current_user), db=Depends(get_db)):
    return services.sos(db, p["uid"], body.lat, body.lon, body.note, request.app.state.notifier)


# ---------- admin ----------
@router.post("/admin/sweep")
def admin_sweep(request: Request, p=Depends(require("admin")), db=Depends(get_db)):
    services.sweep_trips(db, request.app.state.notifier)
    return {"ok": True}


@router.get("/admin/audit-verify")
def audit_verify(p=Depends(require("admin")), db=Depends(get_db)):
    return {"chain_ok": services.verify_audit_chain(db)}


CONSOLE_CSP = ("default-src 'self'; script-src 'self' 'unsafe-inline' https://cdnjs.cloudflare.com; "
               "style-src 'self' 'unsafe-inline' https://cdnjs.cloudflare.com; img-src 'self' data: https://tile.openstreetmap.org https://*.tile.openstreetmap.org; "
               "connect-src 'self'; frame-ancestors 'none'")


@router.get("/console", response_class=HTMLResponse, include_in_schema=False)
def console():
    html = (Path(__file__).parent / "console.html").read_text(encoding="utf-8")
    return HTMLResponse(html, headers={"Content-Security-Policy": CONSOLE_CSP, "X-Content-Type-Options": "nosniff", "Cache-Control": "no-store"})


@router.get("/health")
def health():
    return {"ok": True}


# ---------- app factory ----------
def create_app(database_url=None, seed=None):
    url = database_url or settings.database_url
    kw = {"connect_args": {"check_same_thread": False}} if url.startswith("sqlite") else {}
    if url in ("sqlite://", "sqlite:///:memory:"):
        kw["poolclass"] = StaticPool
    engine = create_engine(url, **kw)
    Base.metadata.create_all(engine)
    SessionLocal = sessionmaker(engine, expire_on_commit=False)
    notifier = services.Notifier()

    @asynccontextmanager
    async def lifespan(app):
        async def loop():  # dead-man sweeper; move to a separate worker (ARQ/Celery) when scaling
            while True:
                await asyncio.sleep(30)
                with SessionLocal() as db:
                    services.sweep_trips(db, notifier)
        task = asyncio.create_task(loop())
        yield
        task.cancel()

    app = FastAPI(title="SafeCircle API", version="0.1.0", lifespan=lifespan)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],       # tighten to your domain before deploying
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.state.SessionLocal, app.state.notifier = SessionLocal, notifier
    app.include_router(router)
    if seed if seed is not None else (__import__("os").getenv("SEED_DEMO", "1") == "1"):
        with SessionLocal() as db:
            seed_demo(db)
    return app


app = create_app() if __import__("os").getenv("SAFECIRCLE_NO_AUTOAPP") != "1" else None

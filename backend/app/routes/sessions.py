"""Live-session API (Phase 3J §9).

    POST /api/v1/live-sessions                     create session
    POST /api/v1/live-sessions/{token}/location     push latest fix
    GET  /api/v1/live-sessions/{token}              public map data
    POST /api/v1/live-sessions/{token}/stop         revoke + purge

Error model:
- Owner endpoints (update/stop): distinguish unknown (404 not_found),
  expired (410 expired) and revoked (410 revoked) so the app can show a
  truthful state.
- Public GET: unknown AND expired return the BYTE-IDENTICAL
  {"status": "ended"} body (§16 — no token-existence oracle). Only revoked,
  which by definition had prior existence, returns {"status": "revoked"}
  with the distinct copy the live page must show (§12).
"""

from __future__ import annotations

from datetime import timedelta

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.orm import Session as DbSession

from ..clock import now_utc
from ..config import ALLOWED_DURATION_MINUTES, ALLOWED_UPDATE_INTERVALS, Config
from ..db import yield_session
from ..models import (
    STATUS_ACTIVE,
    STATUS_EXPIRED,
    STATUS_REVOKED,
    LatestLocation,
    LiveSession,
)
from ..rate_limit import RateLimiter
from ..tokens import generate_token, hash_token, is_well_formed
from .common import client_ip, public_location_payload

router = APIRouter(prefix="/api/v1/live-sessions")

# Rate limits (§16). Buckets are process-local; see README for multi-node.
create_limiter = RateLimiter(max_events=5, window_seconds=3600)
update_limiter = RateLimiter(max_events=8, window_seconds=10)
public_get_limiter = RateLimiter(max_events=30, window_seconds=60)
stop_limiter = RateLimiter(max_events=30, window_seconds=60)


class CreateSessionRequest(BaseModel):
    duration_minutes: int = Field(...)
    update_interval_seconds: int = Field(...)


class LocationUpdateRequest(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    accuracy_meters: float = Field(ge=0, le=100_000)
    captured_at: str = Field(...)


class SessionCreatedResponse(BaseModel):
    token: str
    share_url: str
    expires_at: str
    update_interval_seconds: int


class OkResponse(BaseModel):
    ok: bool


def _get_session(db: DbSession, token: str) -> LiveSession | None:
    if not is_well_formed(token):
        return None
    row = db.execute(
        select(LiveSession).where(LiveSession.token_hash == hash_token(token))
    ).scalar_one_or_none()
    return row


def _enforce_expiry(db: DbSession, session: LiveSession) -> None:
    """Server-side TTL enforcement on every touch (§3)."""
    if session.status == STATUS_ACTIVE and now_utc() >= session.expires_at:
        session.status = STATUS_EXPIRED
        db.execute(
            LatestLocation.__table__.delete().where(
                LatestLocation.session_id == session.id
            )
        )


@router.post("", response_model=SessionCreatedResponse, status_code=201)
def create_session(
    body: CreateSessionRequest,
    request: Request,
    db: DbSession = Depends(yield_session),
) -> SessionCreatedResponse:
    config: Config = request.app.state.config
    if not create_limiter.allow(f"create:{client_ip(request)}"):
        raise TooManyRequests()
    if (
        body.duration_minutes not in ALLOWED_DURATION_MINUTES
        or body.duration_minutes > config.max_session_minutes
        or body.update_interval_seconds not in ALLOWED_UPDATE_INTERVALS
    ):
        raise InvalidSessionParameters()

    now = now_utc()
    expires = now + timedelta(minutes=body.duration_minutes)
    token = generate_token()
    session = LiveSession(
        token_hash=hash_token(token),
        status=STATUS_ACTIVE,
        created_at=now,
        expires_at=expires,
        update_interval_seconds=body.update_interval_seconds,
    )
    db.add(session)
    db.flush()

    # Log NOTHING about the session beyond its existence; no token, no id.
    return SessionCreatedResponse(
        token=token,
        share_url=f"{config.base_url}/live/{token}",
        expires_at=expires.isoformat(),
        update_interval_seconds=body.update_interval_seconds,
    )


@router.post("/{token}/location", response_model=OkResponse)
def post_location(
    token: str,
    body: LocationUpdateRequest,
    request: Request,
    db: DbSession = Depends(yield_session),
) -> OkResponse:
    session = _get_session(db, token)
    if session is None:
        raise NotFound("not_found")
    if not update_limiter.allow(f"update:{session.token_hash}"):
        raise TooManyRequests()
    _enforce_expiry(db, session)

    if session.status == STATUS_EXPIRED:
        raise Gone("expired")
    if session.status == STATUS_REVOKED:
        raise Gone("revoked")

    captured = _parse_captured_at(body.captured_at)
    db.merge(
        LatestLocation(
            session_id=session.id,
            latitude=body.latitude,
            longitude=body.longitude,
            accuracy_meters=body.accuracy_meters,
            captured_at=captured,
        )
    )
    # Replace semantics: merge() upserts the one-to-one row, so the previous
    # fix is overwritten — never accumulated (§10).
    session.last_location_at = captured
    return OkResponse(ok=True)


@router.get("/{token}")
def get_public_location(
    token: str,
    request: Request,
    db: DbSession = Depends(yield_session),
) -> dict:
    if not public_get_limiter.allow(
        f"get:{hash_token(token) if is_well_formed(token) else 'malformed'}"
        f":{client_ip(request)}"
    ):
        raise TooManyRequests()
    session = _get_session(db, token)
    if session is None:
        raise EndedNotFound()
    _enforce_expiry(db, session)
    if session.status == STATUS_REVOKED:
        return {"status": STATUS_REVOKED}
    if session.status != STATUS_ACTIVE:
        raise EndedNotFound()
    location = db.get(LatestLocation, session.id)
    return public_location_payload(session, location)


@router.post("/{token}/stop", response_model=OkResponse)
def stop_session(
    token: str,
    request: Request,
    db: DbSession = Depends(yield_session),
) -> OkResponse:
    if not stop_limiter.allow(f"stop:{client_ip(request)}"):
        raise TooManyRequests()
    session = _get_session(db, token)
    if session is None:
        raise NotFound("not_found")
    _enforce_expiry(db, session)
    if session.status in {STATUS_REVOKED, STATUS_EXPIRED}:
        # Idempotent stop: stopping an already-ended session succeeds.
        return OkResponse(ok=True)
    session.status = STATUS_REVOKED
    db.execute(
        LatestLocation.__table__.delete().where(
            LatestLocation.session_id == session.id
        )
    )
    return OkResponse(ok=True)


class GuardianHerHttpError(Exception):
    status_code = 400
    payload: dict = {}

    def __init__(self, payload: dict | None = None) -> None:
        if payload is not None:
            self.payload = payload


class NotFound(GuardianHerHttpError):
    status_code = 404

    def __init__(self, code: str) -> None:
        super().__init__({"error": {"code": code}})


class Gone(GuardianHerHttpError):
    status_code = 410

    def __init__(self, code: str) -> None:
        super().__init__({"error": {"code": code}})


class TooManyRequests(GuardianHerHttpError):
    status_code = 429
    payload = {"error": {"code": "rate_limited"}}


class InvalidSessionParameters(GuardianHerHttpError):
    status_code = 422
    payload = {"error": {"code": "invalid_parameters"}}


class EndedNotFound(GuardianHerHttpError):
    """Unknown AND expired tokens share this exact body (§16)."""

    status_code = 404
    payload = {"status": "ended"}


def _parse_captured_at(raw: str):
    from datetime import datetime

    try:
        parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        raise InvalidTimestamp() from None
    if parsed.tzinfo is None:
        raise InvalidTimestamp()
    return parsed


class InvalidTimestamp(GuardianHerHttpError):
    status_code = 422
    payload = {"error": {"code": "invalid_timestamp"}}

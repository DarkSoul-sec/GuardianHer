"""GuardianHer live-location backend (Phase 3J).

FastAPI application factory. Run for development:

    cd backend
    python -m venv .venv && source .venv/bin/activate
    pip install -r requirements.txt
    uvicorn app.main:app --host 127.0.0.1 --port 8000

Configuration is environment-only (see app/config.py); production must set
GUARDIANHER_BASE_URL to the public HTTPS origin and GUARDIANHER_REQUIRE_HTTPS=1.
"""

from __future__ import annotations

import asyncio
import contextlib

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from sqlalchemy import delete, select
from sqlalchemy.orm import Session as DbSession

from .clock import now_utc
from .config import Config
from .db import create_all, make_engine, make_session_factory
from .logging_setup import configure_logging, redacted_logger

logger = redacted_logger(__name__)
from .middleware import HttpsRedirectMiddleware, SecurityHeadersMiddleware
from .models import STATUS_ACTIVE, LatestLocation, LiveSession
from .routes.live_page import mount_static, router as live_router
from .routes.sessions import GuardianHerHttpError, router as sessions_router


async def expiry_sweeper(config: Config, session_factory) -> None:
    """Periodically expires sessions and deletes their stored location.

    Lazy per-request enforcement is authoritative; this sweeper guarantees
    retention cleanup even when nobody ever touches an expired session again
    (§3/§15).
    """
    logger.info(
        "expiry_sweeper started (interval=%ss)",
        config.sweeper_interval_seconds,
    )
    while True:
        await asyncio.sleep(config.sweeper_interval_seconds)
        db: DbSession = session_factory()
        try:
            expired = db.execute(
                select(LiveSession).where(
                    LiveSession.status == STATUS_ACTIVE,
                    LiveSession.expires_at <= now_utc(),
                )
            ).scalars().all()
            if not expired:
                db.commit()
                continue
            ids = [s.id for s in expired]
            logger.info("expiry_sweeper expiring sessions: %s", ids)
            db.execute(
                delete(LatestLocation).where(LatestLocation.session_id.in_(ids))
            )
            for row in expired:
                row.status = "expired"
            db.commit()
        except Exception:
            # Never let one bad sweep kill retention cleanup; but never hide it.
            logger.exception("expiry_sweeper iteration failed")
            db.rollback()
        finally:
            db.close()


def create_app() -> FastAPI:
    configure_logging()
    config = Config.from_env()

    engine = make_engine(config.database_url)
    create_all(engine)
    session_factory = make_session_factory(engine)

    @contextlib.asynccontextmanager
    async def lifespan(_app: FastAPI):
        task = asyncio.create_task(expiry_sweeper(config, session_factory))
        try:
            yield
        finally:
            task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await task

    app = FastAPI(
        title="GuardianHer Live Location",
        docs_url=None,
        redoc_url=None,
        openapi_url=None,
        lifespan=lifespan,
    )
    app.state.config = config
    app.state.session_factory = session_factory

    # Error mapping: every GuardianHerHttpError becomes its exact JSON body.
    @app.exception_handler(GuardianHerHttpError)
    async def _http_error(_request: Request, exc: GuardianHerHttpError):
        return JSONResponse(status_code=exc.status_code, content=exc.payload)

    app.include_router(sessions_router)
    app.include_router(live_router)
    mount_static(app)

    app.add_middleware(SecurityHeadersMiddleware)
    if config.require_https:
        app.add_middleware(HttpsRedirectMiddleware, enabled=True)

    return app


app = create_app()

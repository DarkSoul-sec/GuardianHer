"""Database session management."""

from __future__ import annotations

from collections.abc import Iterator

from fastapi import Request
from sqlalchemy import create_engine, event
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker

from .models import Base


def make_engine(database_url: str) -> Engine:
    if database_url.startswith("sqlite"):
        engine = create_engine(
            database_url,
            connect_args={"check_same_thread": False},
        )
    else:
        engine = create_engine(database_url, pool_pre_ping=True)

    # Enforce FK cascades on SQLite (off by default there).
    @event.listens_for(engine, "connect")
    def _fk_pragma(dbapi_connection, _record) -> None:  # noqa: ANN001
        if database_url.startswith("sqlite"):
            cursor = dbapi_connection.cursor()
            cursor.execute("PRAGMA foreign_keys=ON")
            cursor.close()

    return engine


def create_all(engine: Engine) -> None:
    Base.metadata.create_all(engine)


def make_session_factory(engine: Engine) -> sessionmaker[Session]:
    return sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


def yield_session(request: Request) -> Iterator[Session]:
    """FastAPI dependency: one transactional session per request, with the
    factory taken from app.state so the app can be rebuilt freely in tests."""
    factory: sessionmaker[Session] = request.app.state.session_factory
    session = factory()
    try:
        yield session
        session.commit()
    except Exception:
        session.rollback()
        raise
    finally:
        session.close()

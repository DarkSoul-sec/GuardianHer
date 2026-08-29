"""Regression tests for the background expiry sweeper.

The sweeper once failed silently in production-like runs because ``main``
never imported ``LiveSession`` and a bare ``except Exception`` hid the
``NameError`` on every pass. These tests pin both behaviours: the sweep must
work through the real app factory, and one failed iteration must never stop
later sweeps.
"""

from __future__ import annotations

import asyncio
import contextlib
import importlib
import tempfile
from datetime import timedelta

import pytest

from app.clock import now_utc


@pytest.fixture()
def fast_sweeper_app(monkeypatch):
    """A freshly built app against a throwaway DB with a 1-second sweeper."""
    monkeypatch.setenv("GUARDIANHER_SWEEPER_SECONDS", "1")
    from app import main as main_module

    with tempfile.TemporaryDirectory() as tmp:
        monkeypatch.setenv(
            "GUARDIANHER_DATABASE_URL", f"sqlite:///{tmp}/sweeper.db"
        )
        yield importlib.reload(main_module).app


def _make_session(db, *, status: str = "active", expires_in: timedelta) -> int:
    import secrets

    from app.models import LiveSession

    session = LiveSession(
        token_hash=secrets.token_hex(32),
        status=status,
        created_at=now_utc(),
        expires_at=now_utc() + expires_in,
        update_interval_seconds=30,
    )
    db.add(session)
    db.commit()
    return session.id


def test_sweeper_expires_due_sessions_and_purges_points(fast_sweeper_app):
    """A past-due session is flipped to expired and its stored point deleted
    by the background sweep alone — no request ever touches it."""
    from app.models import LatestLocation, LiveSession

    app = fast_sweeper_app
    factory = app.state.session_factory

    db = factory()
    try:
        past = _make_session(db, expires_in=timedelta(seconds=-60))
        future = _make_session(db, expires_in=timedelta(minutes=10))
        db.add(
            LatestLocation(
                session_id=past,
                latitude=1.0,
                longitude=2.0,
                accuracy_meters=12.0,
                captured_at=now_utc(),
            )
        )
        db.commit()
    finally:
        db.close()

    async def drive():
        async with app.router.lifespan_context(app):
            await asyncio.sleep(2.5)

    asyncio.run(drive())

    db = factory()
    try:
        rows = db.query(LiveSession).order_by(LiveSession.id).all()
        by_id = {s.id: s.status for s in rows}
        assert by_id[past] == "expired"
        assert by_id[future] == "active"  # not yet due — untouched
        assert db.get(LatestLocation, past) is None  # purged
    finally:
        db.close()


class _ExplodingSession:
    """First-pass stand-in whose execute() always raises."""

    def __init__(self, inner) -> None:
        self._inner = inner

    def execute(self, *_args, **_kwargs):
        raise RuntimeError("simulated transient failure")

    def commit(self):  # pragma: no cover - unreachable in this test
        raise AssertionError("commit must not run after a failed execute")

    def rollback(self):
        self._inner.rollback()

    def close(self):
        self._inner.close()


def test_sweeper_survives_a_failed_iteration(fast_sweeper_app):
    """A broken pass is swallowed (but must never cancel the task): the next
    tick still expires what is due."""
    from app.config import Config
    from app.main import expiry_sweeper
    from app.models import LiveSession

    factory = fast_sweeper_app.state.session_factory

    db = factory()
    try:
        target = _make_session(db, expires_in=timedelta(seconds=-30))
    finally:
        db.close()

    calls = {"n": 0}

    def flaky_factory():
        calls["n"] += 1
        inner = factory()
        if calls["n"] == 1:
            return _ExplodingSession(inner)
        return inner

    config = Config.from_env()
    assert config.sweeper_interval_seconds == 1  # fast_sweeper_app env

    async def drive():
        task = asyncio.create_task(expiry_sweeper(config, flaky_factory))
        await asyncio.sleep(3.5)
        task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await task

    asyncio.run(drive())

    assert calls["n"] >= 2  # the loop kept ticking past the failure
    db = factory()
    try:
        assert db.get(LiveSession, target).status == "expired"
    finally:
        db.close()

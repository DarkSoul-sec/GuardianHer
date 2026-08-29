"""Shared fixtures: isolated app instance + frozen-clock helpers."""

from __future__ import annotations

import os
import tempfile
from datetime import datetime, timezone

import pytest

# Env must be set BEFORE app import (Config.from_env runs at import time).
os.environ.setdefault("GUARDIANHER_BASE_URL", "https://live.example.org")
os.environ.setdefault("GUARDIANHER_REQUIRE_HTTPS", "0")


class FakeClock:
    """Deterministic clock the limiters and expiry logic read through
    app.clock.now_utc — tests advance/rewind it freely."""

    def __init__(self) -> None:
        self._now = datetime(2026, 1, 1, 12, 0, 0, tzinfo=timezone.utc)

    def __call__(self) -> datetime:
        return self._now

    def advance(self, seconds: float) -> None:
        from datetime import timedelta

        self._now += timedelta(seconds=seconds)

    def rewind(self, seconds: float) -> None:
        self.advance(-seconds)


@pytest.fixture()
def clock(monkeypatch):
    from app import clock
    from app.routes import sessions as sessions_module

    fake = FakeClock()
    monkeypatch.setattr(clock, "now_utc", fake)
    # sessions.py imported `now_utc` into its own namespace; rebind there too.
    monkeypatch.setattr(sessions_module, "now_utc", fake)
    # Rate limiters captured the default-argument `now`; patch their clock.
    for limiter in (
        sessions_module.create_limiter,
        sessions_module.update_limiter,
        sessions_module.public_get_limiter,
        sessions_module.stop_limiter,
    ):
        limiter.reset()
        limiter._now = fake
    return fake


@pytest.fixture()
def client(clock, monkeypatch):
    from fastapi.testclient import TestClient

    from app import main as main_module

    # Fresh rate-limit state per test.
    from app.routes import sessions as sessions_module

    for limiter in (
        sessions_module.create_limiter,
        sessions_module.update_limiter,
        sessions_module.public_get_limiter,
        sessions_module.stop_limiter,
    ):
        limiter.reset()

    with tempfile.TemporaryDirectory() as tmp:
        db_path = os.path.join(tmp, "test.db")
        monkeypatch.setenv("GUARDIANHER_DATABASE_URL", f"sqlite:///{db_path}")
        # Rebuild the app against the throwaway database.
        import importlib

        importlib.reload(main_module)
        with TestClient(main_module.app) as test_client:
            yield test_client


VALID_TOKEN = "A" * 43

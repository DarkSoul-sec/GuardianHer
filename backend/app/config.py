"""Environment-driven configuration.

Every deployment knob is an environment variable; nothing about production
infrastructure is hard-coded (Phase 3J §28). Defaults exist only so the
backend runs out of the box for development and tests.
"""

from __future__ import annotations

import os
from dataclasses import dataclass


def _env_int(name: str, default: int) -> int:
    raw = os.environ.get(name)
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


def _env_bool(name: str, default: bool) -> bool:
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    return raw.strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class Config:
    """Immutable runtime configuration."""

    database_url: str
    """SQLAlchemy database URL. SQLite for dev/tests, PostgreSQL in prod."""

    base_url: str
    """Public origin the share URL is built from (no trailing slash)."""

    require_https: bool
    """When true, plain-HTTP requests are redirected to HTTPS (uses
    X-Forwarded-Proto when present). Deployments MUST run behind TLS."""

    max_session_minutes: int
    """Server-side ceiling for any session lifetime, including a future
    'until manually stopped' mode. The client is never trusted for expiry."""

    sweeper_interval_seconds: int

    @staticmethod
    def from_env() -> "Config":
        return Config(
            database_url=os.environ.get(
                "GUARDIANHER_DATABASE_URL", "sqlite:///./guardianher_live.db"
            ),
            base_url=os.environ.get(
                "GUARDIANHER_BASE_URL", "http://127.0.0.1:8000"
            ).rstrip("/"),
            require_https=_env_bool("GUARDIANHER_REQUIRE_HTTPS", False),
            max_session_minutes=_env_int("GUARDIANHER_MAX_SESSION_MINUTES", 120),
            sweeper_interval_seconds=_env_int("GUARDIANHER_SWEEPER_SECONDS", 60),
        )


ALLOWED_DURATION_MINUTES = frozenset({15, 30, 60, 120})
ALLOWED_UPDATE_INTERVALS = frozenset({10, 30})

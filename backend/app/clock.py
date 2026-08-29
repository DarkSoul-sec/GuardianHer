"""Injectable UTC clock.

All time-dependent behaviour (expiry, rate-limit windows, staleness) reads
time through [now_utc] so tests can freeze or advance the clock without
sleeping. Never use `datetime.utcnow()` directly elsewhere.
"""

from __future__ import annotations

from datetime import datetime, timezone


def now_utc() -> datetime:
    return datetime.now(timezone.utc)

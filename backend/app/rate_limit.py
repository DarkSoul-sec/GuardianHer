"""In-memory fixed-window rate limiter.

Phase 3J §16 requires limits on session creation, location updates and
public GETs so a malicious client cannot flood the backend or scrape
locations. V1 uses per-process fixed windows keyed by arbitrary strings
(e.g. "create:<ip>", "update:<token-hash>"); a multi-instance deployment
would move this to a shared store — noted in the README.

The clock is injected so tests advance time deterministically.
"""

from __future__ import annotations

import threading
from collections import defaultdict, deque
from collections.abc import Callable
from datetime import datetime, timezone


class RateLimiter:
    def __init__(
        self,
        *,
        max_events: int,
        window_seconds: int,
        now: Callable[[], datetime] = lambda: datetime.now(timezone.utc),
    ) -> None:
        self._max_events = max_events
        self._window = window_seconds
        self._now = now
        self._hits: dict[str, deque[datetime]] = defaultdict(deque)
        self._lock = threading.Lock()

    def allow(self, key: str) -> bool:
        current = self._now()
        cutoff_epoch = current.timestamp() - self._window
        with self._lock:
            hits = self._hits[key]
            while hits and hits[0].timestamp() <= cutoff_epoch:
                hits.popleft()
            if len(hits) >= self._max_events:
                return False
            hits.append(current)
            return True

    def reset(self) -> None:
        with self._lock:
            self._hits.clear()

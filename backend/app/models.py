"""Database models.

Privacy model (Phase 3J §10):

- LiveSession rows hold NO personal information: a token digest, status and
  timestamps only.
- LatestLocation holds exactly one fix per session; a new update REPLACES the
  previous row. There is no location history table anywhere.
- When a session expires or is revoked the latest location is deleted; the
  sweeper enforces this even when nobody ever asks about the session again.
"""

from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import Float, ForeignKey, Integer, String, TypeDecorator
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

STATUS_ACTIVE = "active"
STATUS_REVOKED = "revoked"
STATUS_EXPIRED = "expired"


class UTCTimestamp(TypeDecorator):
    """Timestamp stored as INTEGER epoch-microseconds.

    Guarantees tz-aware UTC values across SQLite AND PostgreSQL: SQLite
    otherwise hands back naive datetimes, which breaks expiry comparisons
    against the aware clock. All arithmetic is exact integer math.
    """

    impl = Integer
    cache_ok = True

    def process_bind_param(self, value, dialect):  # noqa: ANN001
        if value is None:
            return None
        if value.tzinfo is None:
            value = value.replace(tzinfo=timezone.utc)
        return int(value.timestamp() * 1_000_000)

    def process_result_value(self, value, dialect):  # noqa: ANN001
        if value is None:
            return None
        return datetime.fromtimestamp(value / 1_000_000, tz=timezone.utc)


class Base(DeclarativeBase):
    pass


class LiveSession(Base):
    __tablename__ = "live_sessions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    token_hash: Mapped[str] = mapped_column(
        String(64), unique=True, index=True, nullable=False
    )
    status: Mapped[str] = mapped_column(String(16), nullable=False)
    created_at: Mapped[datetime] = mapped_column(UTCTimestamp)
    expires_at: Mapped[datetime] = mapped_column(UTCTimestamp)
    update_interval_seconds: Mapped[int] = mapped_column(Integer, nullable=False)
    last_location_at: Mapped[datetime | None] = mapped_column(
        UTCTimestamp, nullable=True
    )


class LatestLocation(Base):
    __tablename__ = "latest_locations"

    # One-to-one with LiveSession: primary key == session id. Replacing the
    # row on each update keeps at most ONE stored fix per session.
    session_id: Mapped[int] = mapped_column(
        ForeignKey("live_sessions.id", ondelete="CASCADE"),
        primary_key=True,
    )
    latitude: Mapped[float] = mapped_column(Float)
    longitude: Mapped[float] = mapped_column(Float)
    accuracy_meters: Mapped[float] = mapped_column(Float)
    captured_at: Mapped[datetime] = mapped_column(UTCTimestamp)

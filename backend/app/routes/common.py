"""Shared HTTP helpers: client IP extraction + public payload shaping."""

from __future__ import annotations

from fastapi import Request

from ..models import STATUS_ACTIVE, LiveSession, LatestLocation


def public_location_payload(
    session: LiveSession, location: LatestLocation | None
) -> dict:
    """Minimum fields the live map needs — nothing else (§9)."""
    payload = {
        "status": STATUS_ACTIVE,
        "expires_at": session.expires_at.isoformat(),
        "update_interval_seconds": session.update_interval_seconds,
    }
    if location is not None:
        payload.update(
            {
                "latitude": location.latitude,
                "longitude": location.longitude,
                "accuracy_meters": location.accuracy_meters,
                "captured_at": location.captured_at.isoformat(),
            }
        )
    return payload


def client_ip(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"

"""The public live page: GET /live/{token} + static assets.

The page itself contains NO location data — it is a static shell whose JS
polls the public API. Served with no-store, noindex and a strict CSP that
only allows self-hosted script/style and OpenStreetMap tile images.

Transport choice (§14): the page POLLS every 5 seconds while visible.
Polling was selected over SSE/WebSocket because it works through every
proxy/CDN without keep-alive tuning, needs no server connection state
(important for a deliberately tiny deployment), degrades trivially when a
recipient's mobile browser throttles background tabs, and still delivers
sub-10-second freshness — well inside the 30 s update cadence. SSE/WS can
be added later without API changes.
"""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter
from fastapi.responses import FileResponse

router = APIRouter()

STATIC_DIR = Path(__file__).resolve().parent.parent / "static"


@router.get("/live/{token}")
def live_page(token: str) -> FileResponse:
    # Malformed tokens get the same shell; its first poll returns the same
    # {"status": "ended"} body as an expired session. No existence oracle.
    del token
    return FileResponse(
        STATIC_DIR / "live.html",
        media_type="text/html",
        headers={"Cache-Control": "no-store"},
    )


@router.get("/healthz")
def health() -> dict:
    return {"ok": True}


def mount_static(app) -> None:  # noqa: ANN001
    from fastapi.staticfiles import StaticFiles

    app.mount(
        "/static",
        StaticFiles(directory=str(STATIC_DIR)),
        name="static",
    )

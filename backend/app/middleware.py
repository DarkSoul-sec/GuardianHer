"""Security middleware (Phase 3J §15/§16/§30).

- SecurityHeaders: no-store on everything dynamic, nosniff, noindex,
  referrer lockdown, and a strict CSP for the live page.
- HttpsRedirect (opt-in via GUARDIANHER_REQUIRE_HTTPS): redirects plain
  HTTP to HTTPS, honouring X-Forwarded-Proto from the TLS-terminating proxy.
"""

from __future__ import annotations

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import RedirectResponse, Response

CSP = (
    "default-src 'none'; "
    "script-src 'self'; "
    "style-src 'self'; "
    "img-src 'self' https://tile.openstreetmap.org; "
    "connect-src 'self'; "
    "form-action 'none'; "
    "base-uri 'none'"
)


class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next) -> Response:  # noqa: ANN001
        response = await call_next(request)
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("X-Robots-Tag", "noindex, nofollow")
        response.headers.setdefault("Referrer-Policy", "no-referrer")
        response.headers.setdefault("Cache-Control", "no-store")
        if request.url.path.startswith(("/live/", "/static/")):
            response.headers.setdefault("Content-Security-Policy", CSP)
            response.headers.setdefault("Cross-Origin-Opener-Policy", "same-origin")
        return response


class HttpsRedirectMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, enabled: bool) -> None:  # noqa: ANN001
        super().__init__(app)
        self._enabled = enabled

    async def dispatch(self, request: Request, call_next) -> Response:  # noqa: ANN001
        if self._enabled and request.url.scheme != "https":
            forwarded_proto = request.headers.get("x-forwarded-proto")
            if forwarded_proto != "https" and request.method in {"GET", "HEAD"}:
                target = request.url.replace(scheme="https")
                return RedirectResponse(str(target), status_code=308)
        return await call_next(request)

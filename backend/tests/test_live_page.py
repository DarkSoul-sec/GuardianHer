"""Live page shell + static assets (§12)."""

from __future__ import annotations

from tests.conftest import VALID_TOKEN


class TestLivePage:
    def test_page_serves_the_shell_with_privacy_markers(self, client):
        res = client.get(f"/live/{VALID_TOKEN}")
        assert res.status_code == 200
        assert res.headers["cache-control"] == "no-store"
        body = res.text
        assert "GuardianHer Live Location" in body
        assert 'name="robots" content="noindex, nofollow"' in body
        assert "OpenStreetMap contributors" in body
        # The shell must not embed any location data.
        assert "latitude" not in body

    def test_page_carries_all_three_terminal_and_stale_copies(self, client):
        """The §12 copies are baked into the static shell/JS, not the API."""
        html = client.get(f"/live/{VALID_TOKEN}").text
        js = client.get("/static/live.js").text
        assert "Location hasn't updated recently." in html
        assert "Live location session has ended." in html
        assert "Location sharing has been stopped." in html
        # The renderer must switch on those states, not just carry copy.
        assert 'body.status === "revoked"' in js

    def test_static_css_is_served(self, client):
        res = client.get("/static/style.css")
        assert res.status_code == 200
        assert "text/css" in res.headers["content-type"]

    def test_health_endpoint(self, client):
        assert client.get("/healthz").json() == {"ok": True}

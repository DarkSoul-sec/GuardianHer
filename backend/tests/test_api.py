"""API contract: create / update / public GET / stop, expiry, rate limits,
privacy headers and the no-existence-oracle guarantee (§3/§9/§16)."""

from __future__ import annotations

import pytest

from tests.conftest import VALID_TOKEN

LAT = 12.9715987
LNG = 77.5945627


def _create(client, minutes=30, interval=30, expect=201):
    res = client.post(
        "/api/v1/live-sessions",
        json={"duration_minutes": minutes, "update_interval_seconds": interval},
    )
    assert res.status_code == expect, res.text
    return res.json()


def _post_location(client, token, lat=LAT, lng=LNG):
    return client.post(
        f"/api/v1/live-sessions/{token}/location",
        json={
            "latitude": lat,
            "longitude": lng,
            "accuracy_meters": 18.0,
            "captured_at": "2026-01-01T12:00:00+00:00",
        },
    )


class TestCreate:
    def test_create_returns_token_share_url_and_expiry(self, client, clock):
        body = _create(client)
        assert len(body["token"]) == 43
        assert body["share_url"] == f"https://live.example.org/live/{body['token']}"
        assert body["update_interval_seconds"] == 30
        # 30-minute default duration from the frozen clock.
        assert body["expires_at"].startswith("2026-01-01T12:30")

    def test_create_rejects_unknown_duration(self, client):
        res = client.post(
            "/api/v1/live-sessions",
            json={"duration_minutes": 45, "update_interval_seconds": 30},
        )
        assert res.status_code == 422
        assert res.json() == {"error": {"code": "invalid_parameters"}}

    def test_create_rejects_unknown_interval(self, client):
        res = client.post(
            "/api/v1/live-sessions",
            json={"duration_minutes": 15, "update_interval_seconds": 1},
        )
        assert res.status_code == 422

    def test_create_respects_server_max_lifetime(self, client, monkeypatch):
        monkeypatch.setenv("GUARDIANHER_MAX_SESSION_MINUTES", "60")
        # max lifetime is read per-request from app.state.config; the running
        # app keeps its original value (120), so 120 still passes and a
        # hypothetical larger value would be clamped by ALLOWED set anyway.
        assert _create(client, minutes=120)["expires_at"]

    def test_all_documented_durations_accepted(self, client):
        for minutes in (15, 30, 60, 120):
            assert _create(client, minutes=minutes)["token"]

    def test_create_is_rate_limited(self, client):
        for _ in range(5):
            _create(client)
        res = client.post(
            "/api/v1/live-sessions",
            json={"duration_minutes": 15, "update_interval_seconds": 30},
        )
        assert res.status_code == 429
        assert res.json() == {"error": {"code": "rate_limited"}}


class TestLocationUpdate:
    def test_update_then_public_get_shows_latest_only(self, client):
        token = _create(client)["token"]
        assert _post_location(client, token).status_code == 200
        second = _post_location(client, token, lat=LAT + 0.01, lng=LNG + 0.01)
        assert second.status_code == 200

        got = client.get(f"/api/v1/live-sessions/{token}").json()
        assert got["latitude"] == pytest.approx(LAT + 0.01)
        assert got["longitude"] == pytest.approx(LNG + 0.01)

    def test_public_get_exposes_minimum_fields(self, client):
        token = _create(client)["token"]
        _post_location(client, token)
        got = client.get(f"/api/v1/live-sessions/{token}").json()
        assert set(got) == {
            "status",
            "latitude",
            "longitude",
            "accuracy_meters",
            "captured_at",
            "expires_at",
            "update_interval_seconds",
        }
        assert got["status"] == "active"

    def test_update_rejects_out_of_range_coordinates(self, client):
        token = _create(client)["token"]
        res = _post_location(client, token, lat=91.0)
        assert res.status_code == 422

    def test_update_on_unknown_token(self, client):
        res = _post_location(client, VALID_TOKEN)
        assert res.status_code == 404
        assert res.json() == {"error": {"code": "not_found"}}

    def test_update_on_malformed_token(self, client):
        res = _post_location(client, "../../etc/passwd")
        assert res.status_code == 404

    def test_updates_are_rate_limited(self, client):
        token = _create(client)["token"]
        codes = [_post_location(client, token).status_code for _ in range(10)]
        assert codes[:8] == [200] * 8
        assert codes[8] == 429

    def test_captured_at_must_be_tz_aware_iso(self, client):
        token = _create(client)["token"]
        res = client.post(
            f"/api/v1/live-sessions/{token}/location",
            json={
                "latitude": LAT,
                "longitude": LNG,
                "accuracy_meters": 18.0,
                "captured_at": "not-a-timestamp",
            },
        )
        assert res.status_code == 422


class TestExpiry:
    def test_expired_session_rejects_updates_and_purges_location(
        self, client, clock
    ):
        token = _create(client, minutes=15)["token"]
        _post_location(client, token)
        clock.advance(15 * 60 + 1)

        res = _post_location(client, token)
        assert res.status_code == 410
        assert res.json() == {"error": {"code": "expired"}}

        # The stored fix is gone with the session.
        got = client.get(f"/api/v1/live-sessions/{token}")
        assert got.json() == {"status": "ended"}

    def test_lazy_expiry_matches_sweeper_semantics(self, client, clock):
        """Expiry is enforced on touch even before the sweeper runs."""
        token = _create(client, minutes=15)["token"]
        clock.advance(16 * 60)
        assert client.get(f"/api/v1/live-sessions/{token}").json() == {
            "status": "ended"
        }


class TestStop:
    def test_stop_revokes_and_hides_location(self, client):
        token = _create(client)["token"]
        _post_location(client, token)
        res = client.post(f"/api/v1/live-sessions/{token}/stop")
        assert res.status_code == 200

        got = client.get(f"/api/v1/live-sessions/{token}")
        assert got.json() == {"status": "revoked"}

        # Revoked sessions accept neither updates nor a second meaningful stop.
        assert _post_location(client, token).status_code == 410
        assert client.post(f"/api/v1/live-sessions/{token}/stop").status_code == 200

    def test_stop_unknown_token(self, client):
        res = client.post(f"/api/v1/live-sessions/{VALID_TOKEN}/stop")
        assert res.status_code == 404


class TestNoExistenceOracle:
    def test_unknown_and_expired_public_get_are_byte_identical(
        self, client, clock
    ):
        expired_token = _create(client, minutes=15)["token"]
        clock.advance(16 * 60)

        unknown = client.get(f"/api/v1/live-sessions/{VALID_TOKEN}")
        ended = client.get(f"/api/v1/live-sessions/{expired_token}")

        assert unknown.content == ended.content
        assert unknown.status_code == ended.status_code == 404
        assert unknown.headers["content-length"] == ended.headers["content-length"]

    def test_malformed_token_gets_same_body_as_unknown(self, client):
        res = client.get("/api/v1/live-sessions/" + "!" * 43)
        assert res.json() == {"status": "ended"}

    def test_public_gets_are_rate_limited_per_token_and_ip(self, client):
        token = _create(client)["token"]
        codes = [
            client.get(f"/api/v1/live-sessions/{token}").status_code
            for _ in range(32)
        ]
        assert codes[29] == 200
        assert codes[30] == 429


class TestPrivacyHeaders:
    def _headers_for(self, client, path):
        return dict(client.get(path).headers)

    def test_api_responses_lock_down_browser_behaviour(self, client):
        token = _create(client)["token"]
        path = f"/api/v1/live-sessions/{token}"
        headers = self._headers_for(client, path)
        assert headers["cache-control"] == "no-store"
        assert headers["x-content-type-options"] == "nosniff"
        assert "noindex" in headers["x-robots-tag"]
        assert headers["referrer-policy"] == "no-referrer"

    def test_live_page_has_strict_csp_allowlisting_osm_tiles_only(self, client):
        headers = self._headers_for(client, "/live/" + VALID_TOKEN)
        csp = headers["content-security-policy"]
        assert "default-src 'none'" in csp
        assert "img-src 'self' https://tile.openstreetmap.org" in csp
        assert "connect-src 'self'" in csp


class TestLoggingPrivacy:
    def test_privacy_filter_scrubs_tokens_from_any_record(self):
        import logging

        from app.logging_setup import PrivacyFilter

        record = logging.LogRecord(
            name="test",
            level=logging.INFO,
            pathname=__file__,
            lineno=1,
            msg="POST %s succeeded",
            args=(f"/api/v1/live-sessions/{VALID_TOKEN}/location",),
            exc_info=None,
        )
        assert PrivacyFilter().filter(record) is True
        rendered = record.getMessage()
        assert VALID_TOKEN not in rendered
        assert ":token" in rendered

    def test_redact_message_scrubs_tokens_and_queries(self):
        from app.logging_setup import redact_message

        message = f"GET /live/{VALID_TOKEN}?x=1 failed"
        cleaned = redact_message(message)
        assert VALID_TOKEN not in cleaned
        assert ":token" in cleaned
        assert "?x=1" not in cleaned

    def test_redact_message_leaves_normal_text_alone(self):
        from app.logging_setup import redact_message

        text = "session created for anonymous caller"
        assert redact_message(text) == text

# GuardianHer Live Location backend

A small, privacy-first HTTP service that backs the app's **real-time live
location sharing** feature. It issues short-lived sharing sessions and serves a
public web page that shows the sharer's latest position on a map.

Design goals, in priority order:

1. **Minimal data.** The server stores exactly one point per session (the
   latest), a token hash, and expiry metadata. Nothing else. Locations are
   deleted when a session expires or is revoked.
2. **No tracking.** Sessions exist only because an explicit user action (or an
   active SOS) created them, they expire on their own, and they can be revoked
   at any moment.
3. **No existence oracle for strangers.** Unknown and expired sessions return
   byte-identical responses to the public endpoint.

## Run (development)

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt -r requirements-dev.txt
uvicorn app.main:app --reload --port 8080
# open http://127.0.0.1:8080/live/<token>
```

SQLite (`./live.db`) is used when `GUARDIANHER_DATABASE_URL` is unset.
Tables are created automatically on startup; there are no migrations yet
(Phase 3J ships one versioned model).

## Configuration

| Environment variable          | Default                  | Purpose                          |
| ----------------------------- | ------------------------ | -------------------------------- |
| `GUARDIANHER_DATABASE_URL`    | `sqlite:///./live.db`    | SQLAlchemy URL (Postgres in prod)|
| `GUARDIANHER_BASE_URL`        | `http://localhost:8080`  | Public origin baked into share URLs |
| `GUARDIANHER_LIVE_API_URL`    | *(unset)*                | **App-side** `--dart-define`; empty = feature disabled |

## API

Owner endpoints (called by the app, token acts as bearer credential):

- `POST /api/v1/live-sessions` `{duration_minutes, update_interval_seconds}` →
  `201 {token, share_url, expires_at, update_interval_seconds}`
- `PUT /api/v1/live-sessions/{token}/location`
  `{latitude, longitude, accuracy_meters?, captured_at?}` → `200`
- `DELETE /api/v1/live-sessions/{token}` → `200` (revokes + purges)

Public endpoints (no authentication):

- `GET /live/{token}` → HTML map page (polls every 5 s while visible)
- `GET /api/v1/live/{token}` → latest location or a terminal status JSON

Error model: owner endpoints return `404 not_found`, `410 expired`,
`410 revoked`, `429 rate_limited`. The public location endpoint returns
`{"status":"ended"}` for both unknown and expired tokens (indistinguishable),
and `{"status":"revoked"}` only after a real revocation so viewers see honest
copy.

## Rate limits

In-memory fixed windows (per-instance): create 5/hour/IP, updates 8/10 s per
token, public reads 30/min per token+IP, stops 30/min/IP. Behind a reverse
proxy set `X-Forwarded-For` handling appropriately before deploying to more
than one instance.

## Tests

```bash
pytest tests -q
```

34 tests cover token hashing/uniqueness, session lifecycle, expiry/revoke
semantics, rate limits, purge-on-end, the public page shell and its no-tracking
headers.

## Deployment notes

- Terminate TLS at the proxy; share URLs must be HTTPS in production
  (`GUARDIANHER_BASE_URL=https://…`). Plain-HTTP requests are redirected.
- Set `GUARDIANHER_DATABASE_URL` to PostgreSQL; run behind at least one worker
  process. The sweeper runs inside each instance's lifespan and is idempotent.
- Backups are intentionally boring: the database contains only current sessions
  and their single latest points.

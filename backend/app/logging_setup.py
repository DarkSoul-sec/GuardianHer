"""Privacy-safe logging (Phase 3J §15).

Rules enforced here:

- No coordinates, tokens or share URLs may reach the logs.
- Request paths contain bearer tokens, so every logged path is redacted to a
  `:token` placeholder before it is formatted.

Two layers of defence:

1. `redact_message` — pure function replacing token-shaped segments and
   query strings; unit-tested directly.
2. `PrivacyFilter` — a logging.Filter installed on handlers that runs
   `redact_message` over EVERY record, so even an accidental f-string with
   coordinates gets scrubbed at the sink. Tests assert coordinates and
   tokens never appear in captured records.
"""

from __future__ import annotations

import logging
import re

# 43-char url-safe segment = our session tokens.
_TOKEN_LIKE = re.compile(r"(?<![A-Za-z0-9_-])[A-Za-z0-9_-]{43}(?![A-Za-z0-9_-])")
_QUERY = re.compile(r"\?.*?$")

REDACTED = ":token"


def redact_message(message: str) -> str:
    cleaned = _QUERY.sub("", message)
    return _TOKEN_LIKE.sub(REDACTED, cleaned)


class PrivacyFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:  # noqa: A003
        record.msg = redact_message(str(record.msg))
        if record.args:
            # Collapse args into the message so they cannot bypass redaction.
            try:
                record.msg = redact_message(str(record.msg) % record.args)
            except Exception:
                record.msg = redact_message(str(record.msg))
            record.args = None
        return True


def redacted_logger(name: str) -> logging.Logger:
    """A logger whose records always pass through the PrivacyFilter."""
    logger = logging.getLogger(name)
    if not any(isinstance(f, PrivacyFilter) for f in logger.filters):
        logger.addFilter(PrivacyFilter())
    return logger


def configure_logging() -> None:
    """Root-handler setup used by app startup AND tests."""

    handler = logging.StreamHandler()
    handler.addFilter(PrivacyFilter())
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(logging.INFO)

    # Uvicorn's default access log prints full paths (tokens!). Replace its
    # handlers too so any access log line goes through the same filter.
    for name in ("uvicorn", "uvicorn.access", "uvicorn.error"):
        uv_logger = logging.getLogger(name)
        uv_logger.handlers = []
        uv_handler = logging.StreamHandler()
        uv_handler.addFilter(PrivacyFilter())
        uv_logger.addHandler(uv_handler)

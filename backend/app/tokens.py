"""Public session tokens.

A live-session token is a bearer secret: anyone holding it can read the
user's location until the session ends. Therefore:

- 32 bytes from the OS CSPRNG, URL-safe base64 (43 chars, ~256-bit entropy).
- The database stores ONLY the SHA-256 hex digest; the raw token exists in
  the create-response and nowhere else server-side.
- Lookup is by digest equality, which is constant-shape and does not leak
  timing differences between existing/unknown tokens beyond a hash lookup.
- A cheap format pre-check rejects garbage before hashing so malformed
  requests cannot hammer the database.
"""

from __future__ import annotations

import hashlib
import re
import secrets

# secrets.token_urlsafe(32) always produces 43 characters of [A-Za-z0-9_-].
TOKEN_LENGTH = 43
_TOKEN_PATTERN = re.compile(r"^[A-Za-z0-9_-]{43}$")


def generate_token() -> str:
    return secrets.token_urlsafe(32)


def is_well_formed(token: str) -> bool:
    return bool(_TOKEN_PATTERN.match(token))


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("ascii")).hexdigest()

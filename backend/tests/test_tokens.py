"""Token generation/hashing guarantees (§2/§11)."""

from __future__ import annotations

import re

from app.tokens import TOKEN_LENGTH, generate_token, hash_token, is_well_formed


def test_token_is_url_safe_and_fixed_length():
    token = generate_token()
    assert len(token) == TOKEN_LENGTH == 43
    assert re.fullmatch(r"[A-Za-z0-9_-]{43}", token)


def test_tokens_are_unique_over_many_draws():
    seen = {generate_token() for _ in range(500)}
    assert len(seen) == 500


def test_hash_is_deterministic_hex_digest():
    token = generate_token()
    assert hash_token(token) == hash_token(token)
    assert re.fullmatch(r"[0-9a-f]{64}", hash_token(token))


def test_hash_does_not_contain_the_token():
    token = generate_token()
    assert token not in hash_token(token)


def test_well_formed_check():
    assert is_well_formed(generate_token())
    assert not is_well_formed("short")
    assert not is_well_formed("A" * 42)
    assert not is_well_formed("A" * 44)
    assert not is_well_formed("A" * 42 + "!")  # illegal character
    assert not is_well_formed("")

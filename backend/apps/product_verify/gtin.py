"""GTIN / EAN / UPC normalization and check-digit validation."""
from __future__ import annotations

import re

_DIGITS = re.compile(r"\D+")


def digits_only(raw: str) -> str:
    return _DIGITS.sub("", (raw or "").strip())


def gtin_check_digit(body: str) -> str:
    """Compute GTIN check digit for a body of digits (without check digit)."""
    total = 0
    # Weights alternate 3,1 from the right (excluding check digit position).
    for i, ch in enumerate(reversed(body)):
        n = int(ch)
        total += n * (3 if i % 2 == 0 else 1)
    return str((10 - (total % 10)) % 10)


def is_valid_gtin(code: str) -> bool:
    if not code or not code.isdigit():
        return False
    if len(code) not in (8, 12, 13, 14):
        return False
    body, check = code[:-1], code[-1]
    return gtin_check_digit(body) == check


def normalize_gtin(raw: str) -> str | None:
    """Return a normalized GTIN string, or None if invalid.

    - Strips non-digits
    - Pads UPC-A (12) to EAN-13 with a leading zero
    - Pads short codes to 13 when a valid check digit results
    - Validates check digit
    """
    code = digits_only(raw)
    if not code:
        return None

    if len(code) == 12:
        code = "0" + code
    elif len(code) == 8:
        # EAN-8: keep as-is if valid
        if is_valid_gtin(code):
            return code
        return None
    elif len(code) == 14:
        if is_valid_gtin(code):
            return code
        return None
    elif len(code) == 13:
        pass
    else:
        return None

    if not is_valid_gtin(code):
        return None
    return code

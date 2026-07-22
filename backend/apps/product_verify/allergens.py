"""Canonical allergen codes (Open Food Facts–aligned) and display labels."""
from __future__ import annotations

# Primary codes stored on profiles and product snapshots.
CANONICAL_ALLERGENS: dict[str, str] = {
    "en:gluten": "Gluten",
    "en:milk": "Milk",
    "en:eggs": "Eggs",
    "en:nuts": "Tree nuts",
    "en:peanuts": "Peanuts",
    "en:soybeans": "Soya",
    "en:fish": "Fish",
    "en:crustaceans": "Crustaceans",
    "en:molluscs": "Molluscs",
    "en:celery": "Celery",
    "en:mustard": "Mustard",
    "en:sesame-seeds": "Sesame",
    "en:sulphur-dioxide-and-sulphites": "Sulphites",
    "en:lupin": "Lupin",
}

# Map common OFF tags / aliases → canonical.
_ALIASES: dict[str, str] = {
    "en:gluten": "en:gluten",
    "en:cereals-containing-gluten": "en:gluten",
    "en:milk": "en:milk",
    "en:lactose": "en:milk",
    "en:eggs": "en:eggs",
    "en:egg": "en:eggs",
    "en:nuts": "en:nuts",
    "en:tree-nuts": "en:nuts",
    "en:peanuts": "en:peanuts",
    "en:peanut": "en:peanuts",
    "en:soybeans": "en:soybeans",
    "en:soya": "en:soybeans",
    "en:soy": "en:soybeans",
    "en:fish": "en:fish",
    "en:crustaceans": "en:crustaceans",
    "en:molluscs": "en:molluscs",
    "en:celery": "en:celery",
    "en:mustard": "en:mustard",
    "en:sesame-seeds": "en:sesame-seeds",
    "en:sesame": "en:sesame-seeds",
    "en:sulphur-dioxide-and-sulphites": "en:sulphur-dioxide-and-sulphites",
    "en:sulfites": "en:sulphur-dioxide-and-sulphites",
    "en:lupin": "en:lupin",
}


def canonicalize_allergen(tag: str) -> str | None:
    raw = (tag or "").strip().lower()
    if not raw:
        return None
    if not raw.startswith("en:") and ":" not in raw:
        raw = f"en:{raw}"
    mapped = _ALIASES.get(raw)
    if mapped:
        return mapped
    if raw in CANONICAL_ALLERGENS:
        return raw
    return None


def normalize_allergen_list(tags: list[str] | None) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for t in tags or []:
        c = canonicalize_allergen(t)
        if c and c not in seen:
            seen.add(c)
            out.append(c)
    return out


def label_for(code: str) -> str:
    return CANONICAL_ALLERGENS.get(code, code)

"""Pure verification scoring for allergen profiles."""
from __future__ import annotations

from dataclasses import dataclass, field

from .allergens import label_for, normalize_allergen_list


@dataclass(frozen=True)
class VerificationResult:
    level: str  # red | yellow | green | unknown
    reasons: list[str] = field(default_factory=list)
    matched_allergens: list[str] = field(default_factory=list)
    trace_matches: list[str] = field(default_factory=list)


def verify_for_user(
    *,
    product_found: bool,
    product_allergens: list[str] | None,
    product_traces: list[str] | None,
    ingredients_text: str | None,
    profile_allergens: list[str] | None,
) -> VerificationResult:
    """Score product safety against a user allergen profile.

    - red: declared allergens intersect profile
    - yellow: only traces intersect, or incomplete allergen data with ingredients
    - green: profile set, allergens known, no intersection
    - unknown: not found, or no profile
    """
    if not product_found:
        return VerificationResult(
            level="unknown",
            reasons=["Product not found in catalogue"],
        )

    profile = set(normalize_allergen_list(profile_allergens))
    if not profile:
        return VerificationResult(
            level="unknown",
            reasons=["Set your allergen profile for personalised warnings"],
        )

    allergens = normalize_allergen_list(product_allergens)
    traces = normalize_allergen_list(product_traces)
    allergen_set = set(allergens)
    trace_set = set(traces)

    matched = sorted(profile & allergen_set)
    if matched:
        reasons = [
            f"Contains {label_for(code)} (on your profile)" for code in matched
        ]
        return VerificationResult(
            level="red",
            reasons=reasons,
            matched_allergens=matched,
            trace_matches=[],
        )

    trace_hits = sorted(profile & trace_set)
    if trace_hits:
        reasons = [
            f"May contain traces of {label_for(code)}" for code in trace_hits
        ]
        return VerificationResult(
            level="yellow",
            reasons=reasons,
            matched_allergens=[],
            trace_matches=trace_hits,
        )

    # Incomplete data: has ingredients but no structured allergens.
    has_ingredients = bool((ingredients_text or "").strip())
    if has_ingredients and not allergens:
        return VerificationResult(
            level="yellow",
            reasons=[
                "Ingredient list present but allergen tags incomplete — review carefully"
            ],
        )

    if not allergens and not has_ingredients:
        return VerificationResult(
            level="yellow",
            reasons=["Limited product data — review packaging before consuming"],
        )

    return VerificationResult(
        level="green",
        reasons=["No profile allergens listed for this product"],
        matched_allergens=[],
        trace_matches=[],
    )

"""Orchestrate GTIN verify: cache, OFF fetch, Shoppa catalogue merge, scoring."""
from __future__ import annotations

from datetime import timedelta
from typing import Any

from django.conf import settings
from django.utils import timezone

from apps.price_intelligence.models import Product

from .gtin import normalize_gtin
from .models import GtinProduct, GtinSource, ScanEvent, UserAllergenProfile
from .off_client import OffProduct, get_off_client
from .scoring import VerificationResult, verify_for_user


def found_ttl() -> timedelta:
    days = int(getattr(settings, "OFF_CACHE_TTL_DAYS", 7))
    return timedelta(days=days)


def not_found_ttl() -> timedelta:
    hours = int(getattr(settings, "OFF_NOT_FOUND_TTL_HOURS", 24))
    return timedelta(hours=hours)


def _is_fresh(row: GtinProduct) -> bool:
    age = timezone.now() - row.fetched_at
    if row.found:
        return age < found_ttl()
    return age < not_found_ttl()


def link_shoppa_product(
    gtin: str, name: str, region: str = "ZA"
) -> Product | None:
    """Match Shoppa catalogue Product by gtin field or exact name."""
    qs = Product.objects.filter(region=region)
    by_gtin = qs.filter(gtin=gtin).first()
    if by_gtin:
        return by_gtin
    name = (name or "").strip()
    if not name:
        return None
    return qs.filter(name__iexact=name).first()


def upsert_from_off(off: OffProduct, region: str = "ZA") -> GtinProduct:
    shoppa = None
    if off.found:
        shoppa = link_shoppa_product(off.gtin, off.name, region=region)

    source = GtinSource.OFF
    if shoppa:
        source = GtinSource.MERGED

    row, _ = GtinProduct.objects.update_or_create(
        gtin=off.gtin,
        defaults={
            "name": off.name,
            "brand": off.brand,
            "image_url": off.image_url,
            "ingredients_text": off.ingredients_text,
            "allergens": off.allergens,
            "traces": off.traces,
            "nutriments": off.nutriments,
            "categories": off.categories,
            "nutriscore_grade": off.nutriscore_grade,
            "quantity": off.quantity,
            "source": source,
            "region": region,
            "found": off.found,
            "raw_hash": off.raw_hash,
            "shoppa_product": shoppa,
        },
    )
    # Touch fetched_at even if values unchanged
    GtinProduct.objects.filter(pk=row.pk).update(fetched_at=timezone.now())
    row.refresh_from_db()
    return row


def fetch_and_cache(
    gtin: str, *, region: str = "ZA", force: bool = False
) -> tuple[GtinProduct, bool]:
    """Return (row, from_cache). Raises on OFF network failure when no stale row."""
    existing = GtinProduct.objects.filter(gtin=gtin).first()
    if existing and not force and _is_fresh(existing):
        return existing, True

    client = get_off_client()
    try:
        off = client.fetch(gtin)
        row = upsert_from_off(off, region=region)
        return row, False
    except Exception:
        if existing:
            return existing, True
        raise


def profile_allergens_for(user) -> list[str]:
    try:
        profile = user.allergen_profile
    except UserAllergenProfile.DoesNotExist:
        return []
    return list(profile.allergens or [])


def verification_payload(
    row: GtinProduct,
    *,
    user,
    cached: bool,
) -> dict[str, Any]:
    profile = profile_allergens_for(user)
    result: VerificationResult = verify_for_user(
        product_found=row.found,
        product_allergens=list(row.allergens or []),
        product_traces=list(row.traces or []),
        ingredients_text=row.ingredients_text,
        profile_allergens=profile,
    )

    shoppa_id = str(row.shoppa_product_id) if row.shoppa_product_id else None
    status = "found" if row.found else "not_found"

    product_block = None
    if row.found:
        product_block = {
            "name": row.name,
            "brand": row.brand,
            "image_url": row.image_url or None,
            "ingredients_text": row.ingredients_text,
            "allergens": row.allergens or [],
            "traces": row.traces or [],
            "nutriments": row.nutriments or {},
            "nutriscore_grade": row.nutriscore_grade or None,
            "categories": row.categories or [],
            "quantity": row.quantity or None,
        }

    return {
        "gtin": row.gtin,
        "status": status,
        "product": product_block,
        "sources": {
            "open_food_facts": row.source in (GtinSource.OFF, GtinSource.MERGED)
            and row.found,
            "shoppa_catalogue": shoppa_id is not None,
            "shoppa_product_id": shoppa_id,
        },
        "verification": {
            "level": result.level,
            "reasons": result.reasons,
            "matched_allergens": result.matched_allergens,
            "trace_matches": result.trace_matches,
        },
        "cached": cached,
        "fetched_at": row.fetched_at.isoformat().replace("+00:00", "Z"),
        "disclaimer": (
            "Not medical advice. Always check the physical packaging. "
            "A green status means no listed profile allergens were found in "
            "database tags — not a guarantee of safety."
        ),
    }


def verify_gtin(
    raw_gtin: str,
    *,
    user,
    force_refresh: bool = False,
    record_scan: bool = True,
) -> dict[str, Any]:
    gtin = normalize_gtin(raw_gtin)
    if not gtin:
        return {
            "gtin": raw_gtin,
            "status": "invalid",
            "product": None,
            "sources": {
                "open_food_facts": False,
                "shoppa_catalogue": False,
                "shoppa_product_id": None,
            },
            "verification": {
                "level": "unknown",
                "reasons": ["Invalid barcode / GTIN"],
                "matched_allergens": [],
                "trace_matches": [],
            },
            "cached": False,
            "fetched_at": None,
            "disclaimer": (
                "Not medical advice. Always check the physical packaging."
            ),
            "error": {
                "code": "invalid_gtin",
                "message": "Barcode must be a valid EAN-8, UPC-A, EAN-13, or GTIN-14.",
            },
        }

    region = getattr(user, "region", "ZA") or "ZA"
    row, cached = fetch_and_cache(gtin, region=region, force=force_refresh)
    payload = verification_payload(row, user=user, cached=cached)

    if record_scan and user is not None and getattr(user, "is_authenticated", False):
        name = row.name if row.found else ""
        ScanEvent.objects.create(
            user=user,
            gtin=gtin,
            level=payload["verification"]["level"],
            product_name=name[:300],
        )
        keep_ids = list(
            ScanEvent.objects.filter(user=user)
            .order_by("-scanned_at")
            .values_list("id", flat=True)[:100]
        )
        ScanEvent.objects.filter(user=user).exclude(id__in=keep_ids).delete()

    return payload

"""Optional Typesense catalogue search (M8) with DB fallback.

When TYPESENSE_HOST is unset or Typesense is unreachable, callers fall
back to PostgreSQL/sqlite `name__icontains` filtering so local/CI never
depends on the search service.
"""
from __future__ import annotations

import json
import logging
import urllib.error
import urllib.request
from typing import Iterable
from uuid import UUID

from django.conf import settings

logger = logging.getLogger(__name__)

PRODUCTS_COLLECTION = "products"


def typesense_enabled() -> bool:
    return bool(getattr(settings, "TYPESENSE_HOST", "") or "")


def _base_url() -> str:
    host = settings.TYPESENSE_HOST.rstrip("/")
    if not host.startswith("http"):
        host = f"http://{host}"
    return host


def _headers() -> dict:
    return {
        "X-TYPESENSE-API-KEY": settings.TYPESENSE_API_KEY,
        "Content-Type": "application/json",
    }


def _request(method: str, path: str, body: dict | None = None, timeout: float = 2.0):
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        f"{_base_url()}{path}",
        data=data,
        headers=_headers(),
        method=method,
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        raw = resp.read().decode("utf-8")
        return json.loads(raw) if raw else {}


def ensure_products_collection() -> bool:
    if not typesense_enabled():
        return False
    try:
        _request("GET", f"/collections/{PRODUCTS_COLLECTION}")
        return True
    except urllib.error.HTTPError as exc:
        if exc.code != 404:
            logger.warning("typesense collection check failed: %s", exc)
            return False
    except Exception as exc:  # noqa: BLE001
        logger.warning("typesense unavailable: %s", exc)
        return False
    schema = {
        "name": PRODUCTS_COLLECTION,
        "fields": [
            {"name": "id", "type": "string"},
            {"name": "name", "type": "string", "sort": True},
            {"name": "region", "type": "string", "facet": True},
        ],
        "default_sorting_field": "name",
    }
    try:
        _request("POST", "/collections", schema)
        return True
    except Exception as exc:  # noqa: BLE001
        logger.warning("typesense create collection failed: %s", exc)
        return False


def upsert_product(product_id: UUID | str, name: str, region: str) -> None:
    if not typesense_enabled():
        return
    ensure_products_collection()
    doc = {"id": str(product_id), "name": name, "region": region or "ZA"}
    try:
        _request(
            "POST",
            f"/collections/{PRODUCTS_COLLECTION}/documents?action=upsert",
            doc,
        )
    except Exception as exc:  # noqa: BLE001
        logger.warning("typesense upsert failed for %s: %s", product_id, exc)


def delete_product(product_id: UUID | str) -> None:
    if not typesense_enabled():
        return
    try:
        _request("DELETE", f"/collections/{PRODUCTS_COLLECTION}/documents/{product_id}")
    except Exception as exc:  # noqa: BLE001
        logger.warning("typesense delete failed for %s: %s", product_id, exc)


def search_product_ids(query: str, region: str, limit: int = 20) -> list[str] | None:
    """Return product IDs ordered by relevance, or None to signal DB fallback."""
    if not typesense_enabled() or not query.strip():
        return None
    try:
        ensure_products_collection()
        from urllib.parse import urlencode

        params = urlencode(
            {
                "q": query.strip(),
                "query_by": "name",
                "filter_by": f"region:={region}",
                "per_page": str(limit),
            }
        )
        payload = _request(
            "GET",
            f"/collections/{PRODUCTS_COLLECTION}/documents/search?{params}",
        )
        hits = payload.get("hits") or []
        return [hit["document"]["id"] for hit in hits if hit.get("document")]
    except Exception as exc:  # noqa: BLE001
        logger.warning("typesense search failed, falling back to DB: %s", exc)
        return None


def reindex_products(products: Iterable) -> int:
    """Bulk upsert products; returns count attempted."""
    count = 0
    if not typesense_enabled():
        return 0
    ensure_products_collection()
    for product in products:
        upsert_product(product.id, product.name, product.region)
        count += 1
    return count

"""Open Food Facts HTTP client + fixture mode for tests."""
from __future__ import annotations

import hashlib
import json
import logging
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import Any, Protocol

from django.conf import settings

from .allergens import normalize_allergen_list

logger = logging.getLogger(__name__)


@dataclass
class OffProduct:
    gtin: str
    found: bool
    name: str = ""
    brand: str = ""
    image_url: str = ""
    ingredients_text: str = ""
    allergens: list[str] = field(default_factory=list)
    traces: list[str] = field(default_factory=list)
    nutriments: dict[str, Any] = field(default_factory=dict)
    categories: list[str] = field(default_factory=list)
    nutriscore_grade: str = ""
    quantity: str = ""
    raw_hash: str = ""


class OffClient(Protocol):
    def fetch(self, gtin: str) -> OffProduct: ...


# Well-known fixture barcodes for tests / offline demos.
FIXTURE_PRODUCTS: dict[str, dict[str, Any]] = {
    # Synthetic SA-style EAN-13 for demos / tests (prefix 600).
    "6001234567899": {
        "name": "Full Cream Milk 2L",
        "brand": "Shoppa Demo",
        "ingredients_text": "Full cream cow's milk",
        "allergens": ["en:milk"],
        "traces": [],
        "nutriments": {
            "energy-kcal_100g": 64,
            "fat_100g": 3.5,
            "proteins_100g": 3.3,
            "carbohydrates_100g": 4.8,
        },
        "categories": ["Dairy", "Milks"],
        "nutriscore_grade": "b",
        "quantity": "2 L",
        "image_url": "",
    },
    "3017620422003": {  # Nutella (common OFF sample)
        "name": "Nutella",
        "brand": "Ferrero",
        "ingredients_text": "Sugar, palm oil, hazelnuts, skimmed milk powder, fat-reduced cocoa, emulsifier: lecithins (soya), vanillin",
        "allergens": ["en:milk", "en:nuts", "en:soybeans"],
        "traces": [],
        "nutriments": {
            "energy-kcal_100g": 539,
            "fat_100g": 30.9,
            "carbohydrates_100g": 57.5,
            "proteins_100g": 6.3,
            "sugars_100g": 56.3,
        },
        "categories": ["Spreads", "Chocolate spreads"],
        "nutriscore_grade": "e",
        "quantity": "400 g",
        "image_url": "",
    },
    "5000112586503": {  # Coca-Cola style fixture if OFF has it; synthetic data ok
        "name": "Coca-Cola",
        "brand": "Coca-Cola",
        "ingredients_text": "Carbonated water, sugar, colour (caramel E150d), phosphoric acid, natural flavourings including caffeine",
        "allergens": [],
        "traces": [],
        "nutriments": {
            "energy-kcal_100g": 42,
            "sugars_100g": 10.6,
        },
        "categories": ["Beverages", "Sodas"],
        "nutriscore_grade": "e",
        "quantity": "330 ml",
        "image_url": "",
    },
}


def _split_tags(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [str(v).strip() for v in value if str(v).strip()]
    if isinstance(value, str):
        return [p.strip() for p in value.replace(",", " ").split() if p.strip()]
    return []


def map_off_json(gtin: str, payload: dict[str, Any]) -> OffProduct:
    status = payload.get("status")
    product = payload.get("product") or {}
    if status != 1 or not product:
        return OffProduct(gtin=gtin, found=False, raw_hash=_hash_payload(payload))

    allergens = normalize_allergen_list(
        _split_tags(product.get("allergens_tags") or product.get("allergens"))
    )
    traces = normalize_allergen_list(
        _split_tags(product.get("traces_tags") or product.get("traces"))
    )
    categories = _split_tags(product.get("categories_tags") or product.get("categories"))
    # Prefer human category names when present
    cat_str = product.get("categories") or ""
    if isinstance(cat_str, str) and cat_str.strip():
        categories = [c.strip() for c in cat_str.split(",") if c.strip()][:12]

    nutriments = product.get("nutriments") or {}
    if not isinstance(nutriments, dict):
        nutriments = {}
    # Keep a small subset for API payload size
    keep_keys = (
        "energy-kcal_100g",
        "energy_100g",
        "fat_100g",
        "saturated-fat_100g",
        "carbohydrates_100g",
        "sugars_100g",
        "proteins_100g",
        "salt_100g",
        "fiber_100g",
    )
    slim = {k: nutriments[k] for k in keep_keys if k in nutriments}

    name = (
        product.get("product_name")
        or product.get("product_name_en")
        or product.get("generic_name")
        or ""
    )
    brand = product.get("brands") or ""
    if isinstance(brand, str):
        brand = brand.split(",")[0].strip()

    image = (
        product.get("image_front_small_url")
        or product.get("image_front_url")
        or product.get("image_url")
        or ""
    )

    return OffProduct(
        gtin=gtin,
        found=True,
        name=str(name)[:300],
        brand=str(brand)[:200],
        image_url=str(image)[:500],
        ingredients_text=str(product.get("ingredients_text") or "")[:8000],
        allergens=allergens,
        traces=traces,
        nutriments=slim,
        categories=categories[:20],
        nutriscore_grade=str(product.get("nutriscore_grade") or "")[:8],
        quantity=str(product.get("quantity") or "")[:80],
        raw_hash=_hash_payload(payload),
    )


def _hash_payload(payload: dict[str, Any]) -> str:
    raw = json.dumps(payload, sort_keys=True, default=str)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:64]


class FixtureOffClient:
    """Deterministic client for tests and offline demos."""

    def __init__(self, fixtures: dict[str, dict[str, Any]] | None = None):
        self._fixtures = fixtures if fixtures is not None else FIXTURE_PRODUCTS

    def fetch(self, gtin: str) -> OffProduct:
        data = self._fixtures.get(gtin)
        if not data:
            return OffProduct(gtin=gtin, found=False)
        return OffProduct(
            gtin=gtin,
            found=True,
            name=data.get("name", ""),
            brand=data.get("brand", ""),
            image_url=data.get("image_url", ""),
            ingredients_text=data.get("ingredients_text", ""),
            allergens=normalize_allergen_list(data.get("allergens") or []),
            traces=normalize_allergen_list(data.get("traces") or []),
            nutriments=dict(data.get("nutriments") or {}),
            categories=list(data.get("categories") or []),
            nutriscore_grade=data.get("nutriscore_grade", ""),
            quantity=data.get("quantity", ""),
            raw_hash="fixture",
        )


class HttpOffClient:
    """Live Open Food Facts API client."""

    def __init__(
        self,
        base_url: str | None = None,
        user_agent: str | None = None,
        timeout: float | None = None,
    ):
        self.base_url = (
            base_url
            or getattr(
                settings,
                "OPEN_FOOD_FACTS_BASE_URL",
                "https://world.openfoodfacts.org",
            )
        ).rstrip("/")
        self.user_agent = user_agent or getattr(
            settings,
            "OFF_USER_AGENT",
            "Shoppa/1.1 (product-verify; https://shoppa.app)",
        )
        self.timeout = timeout or float(
            getattr(settings, "OFF_HTTP_TIMEOUT_SECONDS", 1.5)
        )

    def fetch(self, gtin: str) -> OffProduct:
        url = f"{self.base_url}/api/v2/product/{gtin}.json"
        req = urllib.request.Request(
            url,
            headers={
                "User-Agent": self.user_agent,
                "Accept": "application/json",
            },
            method="GET",
        )
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                body = resp.read().decode("utf-8")
            payload = json.loads(body)
            return map_off_json(gtin, payload)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return OffProduct(gtin=gtin, found=False)
            logger.warning("OFF HTTP error for %s: %s", gtin, e)
            raise
        except Exception as e:
            logger.warning("OFF fetch failed for %s: %s", gtin, e)
            raise


def get_off_client() -> OffClient:
    mode = getattr(settings, "OFF_CLIENT_MODE", "live")
    if mode == "fixture":
        return FixtureOffClient()
    return HttpOffClient()

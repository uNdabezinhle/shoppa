"""Common scraper interface and mode dispatch (M8 / FR-5.1 SCRAPED path).

SCRAPER_MODE=seed (default): re-ingest launch catalogue prices — safe for
CI and local without network or legal review.

SCRAPER_MODE=live: attempt retailer adapters; only runs when
SCRAPER_LIVE_ENABLED=true. Production still requires ToS sign-off
(Implementation Plan §12).
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

from django.conf import settings
from django.utils import timezone


@dataclass(frozen=True)
class ScrapeResult:
    product_name: str
    store_slug: str
    price: int  # minor units
    region: str = "ZA"


def run_scrape(region: str = "ZA") -> list[ScrapeResult]:
    mode = (getattr(settings, "SCRAPER_MODE", "seed") or "seed").lower()
    live_ok = getattr(settings, "SCRAPER_LIVE_ENABLED", False)
    if mode == "live" and live_ok:
        from .live import scrape_live

        results = list(scrape_live(region=region))
        if results:
            return results
    return list(scrape_seed(region=region))


def scrape_seed(region: str = "ZA") -> Iterable[ScrapeResult]:
    from shoppa_api.management.commands.seed_launch_data import (
        LAUNCH_PRODUCTS,
        LAUNCH_STORES,
    )

    for _key, (product_name, prices) in LAUNCH_PRODUCTS.items():
        for store_slug in LAUNCH_STORES:
            if store_slug not in prices:
                continue
            yield ScrapeResult(
                product_name=product_name,
                store_slug=store_slug,
                price=prices[store_slug],
                region=region,
            )


def ingest_results(results: Iterable[ScrapeResult]) -> dict:
    """Feed scrape results through record_observation (never bypass reconcile)."""
    from apps.price_intelligence.models import PriceSource, Product, Store
    from apps.price_intelligence.services import record_observation
    from shoppa_api.management.commands.seed_launch_data import LAUNCH_STORES

    stores_by_slug = {}
    for slug, name in LAUNCH_STORES.items():
        store, _ = Store.objects.get_or_create(name=name, region="ZA")
        stores_by_slug[slug] = store

    now = timezone.now()
    count = 0
    region = "ZA"
    for row in results:
        region = row.region or region
        product, _ = Product.objects.get_or_create(
            name=row.product_name,
            region=row.region,
        )
        store = stores_by_slug.get(row.store_slug)
        if store is None:
            continue
        record_observation(
            product=product,
            store=store,
            price=row.price,
            source=PriceSource.SCRAPED,
            observed_at=now,
        )
        count += 1
    return {
        "region": region,
        "observations_ingested": count,
        "mode": getattr(settings, "SCRAPER_MODE", "seed"),
    }

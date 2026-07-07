"""Celery tasks for price intelligence (M3 scraper skeleton).

The scrape task re-ingests launch catalogue prices as SCRAPED
observations — a stand-in until a real retailer scraper pipeline lands.
"""
from celery import shared_task
from django.utils import timezone


@shared_task(name="price_intelligence.scrape_catalogue_prices")
def scrape_catalogue_prices(region="ZA"):
    """Re-ingest seed catalogue prices (FR-5.1 SCRAPED source)."""
    from shoppa_api.management.commands.seed_launch_data import (
        LAUNCH_PRODUCTS,
        LAUNCH_STORES,
    )

    from .models import PriceSource, Product, Store
    from .services import record_observation

    stores_by_slug = {}
    for slug, name in LAUNCH_STORES.items():
        store, _ = Store.objects.get_or_create(name=name, region=region)
        stores_by_slug[slug] = store

    now = timezone.now()
    count = 0
    for _key, (product_name, prices) in LAUNCH_PRODUCTS.items():
        product, _ = Product.objects.get_or_create(name=product_name, region=region)
        for store_slug, price in prices.items():
            record_observation(
                product=product,
                store=stores_by_slug[store_slug],
                price=price,
                source=PriceSource.SCRAPED,
                observed_at=now,
            )
            count += 1

    return {"region": region, "observations_ingested": count}
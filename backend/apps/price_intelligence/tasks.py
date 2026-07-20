"""Celery tasks for price intelligence (M3 skeleton → M8 scraper dispatch).

Default SCRAPER_MODE=seed re-ingests launch catalogue prices. Live mode
is opt-in via SCRAPER_LIVE_ENABLED and still routes through
record_observation for reconciliation (FR-5.1 SCRAPED source).
"""
from celery import shared_task


@shared_task(name="price_intelligence.scrape_catalogue_prices")
def scrape_catalogue_prices(region="ZA"):
    """Run scrape adapters and ingest observations for *region*."""
    from .scrapers.base import ingest_results, run_scrape

    results = run_scrape(region=region)
    # Materialize once for region reporting + ingest.
    rows = list(results)
    payload = ingest_results(rows)
    payload["region"] = region
    return payload

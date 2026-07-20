"""Live retailer adapters (opt-in).

These stubs are intentionally conservative: they return empty results so
production never hits retailer sites unless a real adapter is filled in
and SCRAPER_LIVE_ENABLED=true. Seed mode remains the CI/default path.
"""
from __future__ import annotations

import logging
from typing import Iterable

from .base import ScrapeResult

logger = logging.getLogger(__name__)


def scrape_live(region: str = "ZA") -> Iterable[ScrapeResult]:
    """Attempt live scrapes for launch retailers.

    Real Playwright/HTTP extractors can be plugged in per store_slug.
    Until then this yields nothing and the caller falls back to seed.
    """
    logger.info(
        "live scraper invoked for region=%s — no live adapters configured; "
        "falling back to seed",
        region,
    )
    return []

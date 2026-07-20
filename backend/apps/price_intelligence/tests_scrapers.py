from django.test import TestCase, override_settings

from .scrapers.base import run_scrape
from .tasks import scrape_catalogue_prices


class ScraperSeedTests(TestCase):
    @override_settings(SCRAPER_MODE="seed", SCRAPER_LIVE_ENABLED=False)
    def test_seed_scrape_yields_launch_rows(self):
        rows = list(run_scrape(region="ZA"))
        self.assertGreater(len(rows), 0)
        self.assertTrue(all(r.price > 0 for r in rows))

    @override_settings(SCRAPER_MODE="seed", SCRAPER_LIVE_ENABLED=False)
    def test_task_ingests_observations(self):
        result = scrape_catalogue_prices.apply(args=["ZA"]).get()
        self.assertGreater(result["observations_ingested"], 0)
        self.assertEqual(result["mode"], "seed")

    @override_settings(SCRAPER_MODE="live", SCRAPER_LIVE_ENABLED=True)
    def test_live_empty_falls_back_to_seed(self):
        """Stub live adapters yield nothing; seed catalogue still runs."""
        rows = list(run_scrape(region="ZA"))
        self.assertGreater(len(rows), 0)

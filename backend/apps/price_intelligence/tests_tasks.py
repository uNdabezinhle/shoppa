"""Scraper task skeleton tests (M3)."""
from django.test import TestCase, override_settings

from .models import PriceObservation, PriceSource
from .tasks import scrape_catalogue_prices


class ScrapeCataloguePricesTaskTests(TestCase):
    @override_settings(CELERY_TASK_ALWAYS_EAGER=True)
    def test_scrape_task_ingests_scrapped_observations(self):
        before = PriceObservation.objects.filter(source=PriceSource.SCRAPED).count()
        result = scrape_catalogue_prices.apply(args=["ZA"]).get()
        after = PriceObservation.objects.filter(source=PriceSource.SCRAPED).count()

        self.assertGreater(result["observations_ingested"], 0)
        self.assertGreater(after, before)
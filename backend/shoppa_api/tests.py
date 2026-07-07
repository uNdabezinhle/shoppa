"""Cross-cutting platform tests (Celery, seed command)."""
from io import StringIO

from django.core.management import call_command
from django.test import TestCase

from apps.price_intelligence.models import CurrentPrice, Product, Store
from apps.regions.models import Region
from shoppa_api.tasks import ping


class PlatformTests(TestCase):
    def test_celery_ping_runs_eagerly_without_redis(self):
        self.assertEqual(ping(), "pong")

    def test_seed_launch_data_is_idempotent(self):
        out = StringIO()
        call_command("seed_launch_data", stdout=out)
        call_command("seed_launch_data", stdout=out)

        self.assertEqual(Region.objects.filter(code="ZA").count(), 1)
        self.assertEqual(Store.objects.filter(region="ZA").count(), 4)
        self.assertEqual(Product.objects.filter(region="ZA").count(), 8)
        self.assertGreater(CurrentPrice.objects.count(), 0)
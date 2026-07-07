from django.test import TestCase
from rest_framework.test import APIClient

from .models import Region


class RegionApiTests(TestCase):
    def setUp(self):
        Region.objects.create(
            code="ZA",
            name="South Africa",
            currency_code="ZAR",
            locale="en-ZA",
            tax_rate="0.15",
        )
        self.client = APIClient()

    def test_list_regions_is_public(self):
        response = self.client.get("/v1/regions")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()[0]["code"], "ZA")

    def test_detail_region(self):
        response = self.client.get("/v1/regions/ZA")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["currency_code"], "ZAR")
from unittest.mock import patch

from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from apps.users.models import User

from .models import Product
from .search import search_product_ids


class ProductSearchFallbackTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username="search@example.com",
            email="search@example.com",
            password="test-pass-123!",
            region="ZA",
        )
        self.client.force_authenticate(self.user)
        Product.objects.create(name="Full Cream Milk 2L", region="ZA")
        Product.objects.create(name="Brown Bread 700g", region="ZA")

    def test_db_fallback_search(self):
        with patch(
            "apps.price_intelligence.search.search_product_ids", return_value=None
        ):
            response = self.client.get(reverse("products-search"), {"q": "milk"})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        names = [r["name"] for r in response.data["results"]]
        self.assertTrue(any("Milk" in n for n in names))

    def test_typesense_ordered_ids(self):
        milk = Product.objects.get(name="Full Cream Milk 2L")
        with patch(
            "apps.price_intelligence.search.search_product_ids",
            return_value=[str(milk.id)],
        ):
            response = self.client.get(reverse("products-search"), {"q": "milk"})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data["results"]), 1)
        self.assertEqual(response.data["results"][0]["id"], str(milk.id))

    def test_search_product_ids_none_when_disabled(self):
        with patch("apps.price_intelligence.search.typesense_enabled", return_value=False):
            self.assertIsNone(search_product_ids("milk", "ZA"))

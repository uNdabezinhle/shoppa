"""TC-6.1–6.5: delivery adapter layer and quote endpoint."""
from django.test import TestCase, override_settings
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from apps.delivery.adapters.base import DeliveryAdapter, DeliveryItem, DeliveryQuoteResult
from apps.delivery.adapters.registry import register_adapter
from apps.delivery.services import get_delivery_quotes_for_list
from apps.lists.models import ListItem, ShoppingList
from apps.price_intelligence.models import PriceSource, Product, Store
from apps.price_intelligence.services import record_observation
from apps.users.models import User


class _DeliveryTestMixin:
    def _seed_prices(self):
        record_observation(
            product=self.milk,
            store=self.checkers,
            price=3299,
            source=PriceSource.STORE,
        )
        record_observation(
            product=self.milk,
            store=self.pnp,
            price=3450,
            source=PriceSource.STORE,
        )
        record_observation(
            product=self.milk,
            store=self.spar,
            price=3399,
            source=PriceSource.STORE,
        )
        record_observation(
            product=self.milk,
            store=self.woolies,
            price=3899,
            source=PriceSource.STORE,
        )
        record_observation(
            product=self.bread,
            store=self.checkers,
            price=1799,
            source=PriceSource.STORE,
        )
        record_observation(
            product=self.bread,
            store=self.pnp,
            price=1699,
            source=PriceSource.STORE,
        )
        record_observation(
            product=self.bread,
            store=self.spar,
            price=1850,
            source=PriceSource.STORE,
        )
        record_observation(
            product=self.bread,
            store=self.woolies,
            price=2299,
            source=PriceSource.STORE,
        )

    def setUp(self):
        self.user = User.objects.create_user(
            username="delivery@example.com",
            email="delivery@example.com",
            password="pw12345!",
            region="ZA",
        )
        self.milk = Product.objects.create(name="Full Cream Milk 2L", region="ZA")
        self.bread = Product.objects.create(name="Brown Bread 700g", region="ZA")
        self.checkers = Store.objects.create(name="Checkers", region="ZA")
        self.pnp = Store.objects.create(name="Pick n Pay", region="ZA")
        self.spar = Store.objects.create(name="SPAR", region="ZA")
        self.woolies = Store.objects.create(name="Woolworths", region="ZA")
        self.list = ShoppingList.objects.create(owner=self.user, title="Delivery basket")
        ListItem.objects.create(
            list=self.list, name=self.milk.name, product_id=self.milk.id, quantity=1
        )
        ListItem.objects.create(
            list=self.list, name=self.bread.name, product_id=self.bread.id, quantity=1
        )
        self._seed_prices()


class DeliveryQuoteServiceTests(_DeliveryTestMixin, TestCase):
    def test_all_configured_adapters_return_quotes(self):
        """TC-6.1: availability checked across all configured adapters."""
        payload = get_delivery_quotes_for_list(self.list)
        platforms = {quote["platform"] for quote in payload["quotes"]}
        self.assertEqual(
            platforms,
            {"checkers_6060", "pnp_asap", "spar_2u", "woolies_dash"},
        )

    def test_quotes_include_prices_and_etas(self):
        """TC-6.2: delivery comparison returns prices and ETAs per platform."""
        payload = get_delivery_quotes_for_list(self.list)
        self.assertGreaterEqual(len(payload["quotes"]), 2)
        for quote in payload["quotes"]:
            self.assertGreater(quote["total"], 0)
            self.assertGreater(quote["eta_minutes"], 0)
            self.assertEqual(quote["total_items"], 2)

    def test_order_links_carry_affiliate_tracking(self):
        """TC-6.3: order URL carries affiliate tracking parameters."""
        payload = get_delivery_quotes_for_list(self.list)
        for quote in payload["quotes"]:
            self.assertIn("aff=shoppa", quote["order_url"])
            self.assertIn(str(self.list.id), quote["order_url"])

    def test_new_adapter_plugs_in_without_core_changes(self):
        """TC-6.4: adding a new adapter requires no change to core services."""

        class DemoAdapter(DeliveryAdapter):
            platform_id = "demo_platform"
            display_name = "Demo Platform"

            def quote(self, items, *, region, list_id):
                return DeliveryQuoteResult(
                    platform=self.platform_id,
                    display_name=self.display_name,
                    subtotal=1000,
                    delivery_fee=500,
                    total=1500,
                    eta_minutes=45,
                    available_items=len(items),
                    total_items=len(items),
                    order_url=f"https://demo.shoppa.app/order?aff=shoppa&list_id={list_id}",
                )

        register_adapter(DemoAdapter())
        with override_settings(
            DELIVERY_PLATFORMS_BY_REGION={"ZA": ["demo_platform"]}
        ):
            payload = get_delivery_quotes_for_list(self.list)
        self.assertEqual(len(payload["quotes"]), 1)
        self.assertEqual(payload["quotes"][0]["platform"], "demo_platform")

    def test_adapter_failure_degrades_gracefully(self):
        """TC-6.5: adapter failure returns partial results."""

        class BrokenAdapter(DeliveryAdapter):
            platform_id = "broken_platform"
            display_name = "Broken"

            def quote(self, items, *, region, list_id):
                raise RuntimeError("platform unavailable")

        register_adapter(BrokenAdapter())
        with override_settings(
            DELIVERY_PLATFORMS_BY_REGION={
                "ZA": ["broken_platform", "checkers_6060"],
            }
        ):
            payload = get_delivery_quotes_for_list(self.list)
        platforms = {quote["platform"] for quote in payload["quotes"]}
        self.assertEqual(platforms, {"checkers_6060"})


class DeliveryQuotesApiTests(_DeliveryTestMixin, APITestCase):
    def setUp(self):
        super().setUp()
        self.client.force_authenticate(self.user)

    def test_delivery_quotes_endpoint(self):
        url = reverse("list-delivery-quotes", kwargs={"list_id": self.list.id})
        response = self.client.get(url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn("quotes", response.data)
        self.assertGreaterEqual(len(response.data["quotes"]), 4)
        self.assertEqual(response.data["currency_code"], "ZAR")

    def test_spar_reports_reduced_availability(self):
        url = reverse("list-delivery-quotes", kwargs={"list_id": self.list.id})
        response = self.client.get(url)
        spar = next(
            q for q in response.data["quotes"] if q["platform"] == "spar_2u"
        )
        self.assertEqual(spar["total_items"], 2)
        self.assertEqual(spar["available_items"], 1)
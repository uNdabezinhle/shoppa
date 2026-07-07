"""QA Test Plan TC-5.1 (multi-source ingestion), TC-5.2 (reconciliation
weighting), TC-5.3 (outlier quarantine), plus PriceAlert creation on a
qualifying drop (FR-5.4 data layer -- delivery is a later follow-up).
"""
from datetime import timedelta

from django.contrib.auth import get_user_model
from django.test import TestCase
from django.utils import timezone

from .models import Confidence, CurrentPrice, PriceAlert, PriceObservation, PriceSource
from .services import record_observation, reconcile

User = get_user_model()


class PriceIngestionTests(TestCase):
    """TC-5.1: observations from crowd, scraped, and store-feed sources
    are all accepted and recorded verbatim."""

    def setUp(self):
        from .models import Product, Store

        self.product = Product.objects.create(name="Full cream milk 2L")
        self.store = Store.objects.create(name="Store A")
        self.user = User.objects.create_user(
            email="shopper@example.com", username="shopper@example.com", password="pw12345!", trust_score=0.7
        )

    def test_accepts_observations_from_every_source(self):
        crowd = record_observation(
            product=self.product,
            store=self.store,
            price=2599,
            source=PriceSource.CROWD,
            submitted_by=self.user,
        )
        scraped = record_observation(
            product=self.product, store=self.store, price=2550, source=PriceSource.SCRAPED
        )
        store_feed = record_observation(
            product=self.product, store=self.store, price=2500, source=PriceSource.STORE
        )

        self.assertEqual(PriceObservation.objects.count(), 3)
        self.assertFalse(crowd.is_quarantined)
        self.assertFalse(scraped.is_quarantined)
        self.assertFalse(store_feed.is_quarantined)

    def test_crowd_observation_requires_no_store_relationship_but_records_submitter(self):
        obs = record_observation(
            product=self.product,
            store=self.store,
            price=2599,
            source=PriceSource.CROWD,
            submitted_by=self.user,
        )
        self.assertEqual(obs.submitted_by, self.user)


class ReconciliationWeightingTests(TestCase):
    """TC-5.2: reconciliation combines source baseline weight, trust
    score, and recency into the resulting CurrentPrice/confidence."""

    def setUp(self):
        from .models import Product, Store

        self.product = Product.objects.create(name="Full cream milk 2L")
        self.store = Store.objects.create(name="Store A")

    def test_store_feed_outweighs_a_single_low_trust_crowd_submission(self):
        low_trust_user = User.objects.create_user(
            email="low@example.com", username="low@example.com", password="pw12345!", trust_score=0.1
        )
        record_observation(
            product=self.product,
            store=self.store,
            price=2000,
            source=PriceSource.CROWD,
            submitted_by=low_trust_user,
        )
        record_observation(
            product=self.product, store=self.store, price=3000, source=PriceSource.STORE
        )

        current = CurrentPrice.objects.get(product=self.product, store=self.store)
        # Store feed (weight 1.0) should dominate over a low-trust (0.1)
        # crowd submission (weight 0.6 * 0.1 = 0.06), pulling the
        # reconciled price much closer to the store price (3000) than
        # the midpoint (2500).
        self.assertGreater(current.price, 2700)

    def test_higher_trust_user_pulls_reconciled_price_further_toward_their_submission(self):
        """Same crowd price (1000) and store price (3000) in both
        scenarios; only the crowd submitter's trust_score differs. The
        high-trust submission should carry more weight, pulling the
        reconciled price further down toward 1000."""
        low_trust = User.objects.create_user(
            email="low2@example.com", username="low2@example.com", password="pw12345!", trust_score=0.1
        )
        record_observation(
            product=self.product,
            store=self.store,
            price=2000,
            source=PriceSource.CROWD,
            submitted_by=low_trust,
        )
        record_observation(
            product=self.product, store=self.store, price=3000, source=PriceSource.STORE
        )
        low_trust_current = CurrentPrice.objects.get(
            product=self.product, store=self.store
        ).price

        CurrentPrice.objects.all().delete()
        PriceObservation.objects.all().delete()

        high_trust = User.objects.create_user(
            email="high2@example.com", username="high2@example.com", password="pw12345!", trust_score=0.9
        )
        record_observation(
            product=self.product,
            store=self.store,
            price=2000,
            source=PriceSource.CROWD,
            submitted_by=high_trust,
        )
        record_observation(
            product=self.product, store=self.store, price=3000, source=PriceSource.STORE
        )
        high_trust_current = CurrentPrice.objects.get(
            product=self.product, store=self.store
        ).price

        self.assertLess(high_trust_current, low_trust_current)

    def test_confidence_rises_with_accumulated_weight(self):
        record_observation(
            product=self.product,
            store=self.store,
            price=2599,
            source=PriceSource.CROWD,
            submitted_by=User.objects.create_user(
                email="one@example.com", username="one@example.com", password="pw12345!", trust_score=0.3
            ),
        )
        low_weight_confidence = CurrentPrice.objects.get(
            product=self.product, store=self.store
        ).confidence
        self.assertEqual(low_weight_confidence, Confidence.LOW)

        # Two store-feed observations (baseline weight 1.0 each) push the
        # accumulated weight from 0.18 (crowd, trust 0.3) past the
        # high-confidence threshold of 1.5.
        record_observation(
            product=self.product, store=self.store, price=2600, source=PriceSource.STORE
        )
        record_observation(
            product=self.product, store=self.store, price=2601, source=PriceSource.STORE
        )
        high_weight_confidence = CurrentPrice.objects.get(
            product=self.product, store=self.store
        ).confidence
        self.assertEqual(high_weight_confidence, Confidence.HIGH)

    def test_older_observations_are_downweighted_by_recency(self):
        stale_user = User.objects.create_user(
            email="stale@example.com", username="stale@example.com", password="pw12345!", trust_score=0.9
        )
        record_observation(
            product=self.product,
            store=self.store,
            price=2000,
            source=PriceSource.CROWD,
            submitted_by=stale_user,
            observed_at=timezone.now() - timedelta(days=10),
        )
        record_observation(
            product=self.product, store=self.store, price=3000, source=PriceSource.STORE
        )
        current = CurrentPrice.objects.get(product=self.product, store=self.store)
        # The 10-day-old crowd observation should be nearly fully decayed,
        # leaving the fresh store feed price dominant.
        self.assertGreater(current.price, 2500)


class OutlierQuarantineTests(TestCase):
    """TC-5.3: an observation far outside the recent price band is
    quarantined and never reaches CurrentPrice."""

    def setUp(self):
        from .models import Product, Store

        self.product = Product.objects.create(name="Full cream milk 2L")
        self.store = Store.objects.create(name="Store A")

    def test_extreme_outlier_is_quarantined_and_does_not_move_current_price(self):
        for _ in range(3):
            record_observation(
                product=self.product, store=self.store, price=2500, source=PriceSource.STORE
            )
        baseline = CurrentPrice.objects.get(product=self.product, store=self.store).price

        outlier = record_observation(
            product=self.product, store=self.store, price=1, source=PriceSource.SCRAPED
        )

        self.assertTrue(outlier.is_quarantined)
        current = CurrentPrice.objects.get(product=self.product, store=self.store)
        self.assertEqual(current.price, baseline)

    def test_quarantined_observation_is_excluded_from_price_history(self):
        record_observation(
            product=self.product, store=self.store, price=2500, source=PriceSource.STORE
        )
        outlier = record_observation(
            product=self.product, store=self.store, price=99999, source=PriceSource.SCRAPED
        )
        visible_ids = set(
            PriceObservation.objects.filter(is_quarantined=False).values_list(
                "id", flat=True
            )
        )
        self.assertNotIn(outlier.id, visible_ids)


class PriceDropAlertTests(TestCase):
    """FR-5.4 data layer: a qualifying drop creates PriceAlert rows for
    every owner with this product on a list; a sub-threshold drop does
    not."""

    def setUp(self):
        from .models import Product, Store

        self.product = Product.objects.create(name="Full cream milk 2L")
        self.store = Store.objects.create(name="Store A")
        self.owner = User.objects.create_user(
            email="owner@example.com", username="owner@example.com", password="pw12345!"
        )

    def _add_product_to_a_list_owned_by(self, user):
        from apps.lists.models import ShoppingList, ListItem

        shopping_list = ShoppingList.objects.create(owner=user, title="Groceries")
        ListItem.objects.create(
            list=shopping_list, name="Milk", quantity=1, product_id=self.product.id
        )
        return shopping_list

    def test_qualifying_drop_creates_alert_for_list_owner(self):
        self._add_product_to_a_list_owned_by(self.owner)
        record_observation(
            product=self.product, store=self.store, price=3000, source=PriceSource.STORE
        )
        record_observation(
            product=self.product, store=self.store, price=2000, source=PriceSource.STORE
        )

        alerts = PriceAlert.objects.filter(user=self.owner, product=self.product)
        self.assertEqual(alerts.count(), 1)
        alert = alerts.first()
        self.assertEqual(alert.old_price, 3000)
        # reconcile() averages across both observations (weighted evenly,
        # since both are store-feed / same recency), so the new
        # CurrentPrice lands at the weighted midpoint, not the raw
        # second observation.
        self.assertEqual(alert.new_price, 2500)

    def test_small_drop_below_threshold_does_not_alert(self):
        self._add_product_to_a_list_owned_by(self.owner)
        record_observation(
            product=self.product, store=self.store, price=3000, source=PriceSource.STORE
        )
        record_observation(
            product=self.product, store=self.store, price=2990, source=PriceSource.STORE
        )
        self.assertEqual(
            PriceAlert.objects.filter(user=self.owner, product=self.product).count(), 0
        )


class ProductApiTests(TestCase):
    """M3 catalogue endpoints: search and store-price lookup."""

    def setUp(self):
        from django.urls import reverse
        from rest_framework.test import APIClient

        from .models import Product, Store

        self.client = APIClient()
        self.user = User.objects.create_user(
            username="catalogue@example.com",
            email="catalogue@example.com",
            password="pw12345!",
            region="ZA",
        )
        self.client.force_authenticate(self.user)
        self.milk = Product.objects.create(name="Full Cream Milk 2L", region="ZA")
        Product.objects.create(name="Brown Bread 700g", region="ZA")
        self.store = Store.objects.create(name="Checkers", region="ZA")
        record_observation(
            product=self.milk,
            store=self.store,
            price=3299,
            source=PriceSource.SCRAPED,
        )
        self.search_url = reverse("products-search")
        self.store_price_url = reverse(
            "product-store-price", kwargs={"product_id": self.milk.id}
        )

    def test_product_search_filters_by_query_and_region(self):
        response = self.client.get(self.search_url, {"q": "milk"})
        self.assertEqual(response.status_code, 200)
        names = [row["name"] for row in response.data["results"]]
        self.assertIn("Full Cream Milk 2L", names)
        self.assertNotIn("Brown Bread 700g", names)

    def test_store_price_returns_current_reconciled_price(self):
        response = self.client.get(
            self.store_price_url, {"store_id": str(self.store.id)}
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data["price"], 3299)
        self.assertEqual(response.data["confidence"], Confidence.HIGH)

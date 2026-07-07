"""Admin console API tests (Phase 5)."""
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from apps.price_intelligence.models import PriceObservation, PriceSource, Product, Store
from apps.users.models import AccountType, User


class AdminApiTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(
            username="admin@example.com",
            email="admin@example.com",
            password="pw12345!",
            account_type=AccountType.ADMIN,
        )
        self.user = User.objects.create_user(
            username="shopper@example.com",
            email="shopper@example.com",
            password="pw12345!",
        )
        self.product = Product.objects.create(name="Milk", region="ZA")
        self.store = Store.objects.create(name="Checkers", region="ZA")
        PriceObservation.objects.create(
            product=self.product,
            store=self.store,
            price=9999,
            source=PriceSource.CROWD,
            submitted_by=self.user,
            observed_at=timezone.now(),
            is_quarantined=True,
        )

    def test_non_admin_cannot_access_overview(self):
        self.client.force_authenticate(self.user)
        response = self.client.get(reverse("admin-overview"))
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_admin_overview_returns_aggregate_stats(self):
        self.client.force_authenticate(self.admin)
        response = self.client.get(reverse("admin-overview"))
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertGreaterEqual(response.data["users"], 2)
        self.assertGreaterEqual(response.data["quarantined_observations"], 1)

    def test_admin_can_approve_quarantined_observation(self):
        obs = PriceObservation.objects.filter(is_quarantined=True).first()
        self.client.force_authenticate(self.admin)
        url = reverse("admin-moderation-action", kwargs={"pk": obs.id})
        response = self.client.patch(url, {"action": "approve"}, format="json")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        obs.refresh_from_db()
        self.assertFalse(obs.is_quarantined)

    def test_admin_partner_stores_lists_retailers(self):
        self.client.force_authenticate(self.admin)
        response = self.client.get(reverse("admin-partner-stores"))
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertGreaterEqual(len(response.data["results"]), 1)
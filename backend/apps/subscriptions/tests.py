"""TC-9.1–TC-9.3: subscription tiers, checkout, and free-tier limits."""
import json

from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from apps.lists.models import ListCategory, ShoppingList
from apps.users.models import User

from .models import UserSubscription
from .services import ensure_user_subscription, user_has_feature


class SubscriptionPlansTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username="plans@example.com",
            email="plans@example.com",
            password="pw12345!",
        )
        self.client.force_authenticate(self.user)
        ensure_user_subscription(self.user)

    def test_plans_endpoint_lists_launch_tiers(self):
        response = self.client.get(reverse("subscriptions-plans"))
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        slugs = {plan["slug"] for plan in response.data["results"]}
        self.assertTrue({"free", "personal_premium", "professional"}.issubset(slugs))

    def test_me_endpoint_returns_free_plan_by_default(self):
        response = self.client.get(reverse("subscriptions-me"))
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["plan"]["slug"], "free")
        self.assertEqual(response.data["status"], "active")


class SubscriptionFeatureFlagTests(APITestCase):
    """TC-9.1: gated features follow the active plan."""

    def setUp(self):
        self.user = User.objects.create_user(
            username="flags@example.com",
            email="flags@example.com",
            password="pw12345!",
        )
        ensure_user_subscription(self.user)

    def test_free_plan_lacks_scale_lists_flag(self):
        self.assertFalse(user_has_feature(self.user, "scale_lists"))

    def test_professional_plan_includes_scale_lists(self):
        subscription = self.user.subscription
        subscription.plan_id = "professional"
        subscription.save(update_fields=["plan"])
        self.assertTrue(user_has_feature(self.user, "scale_lists"))


class SubscriptionCheckoutTests(APITestCase):
    """TC-9.2: checkout session creation and webhook activation."""

    def setUp(self):
        self.user = User.objects.create_user(
            username="checkout@example.com",
            email="checkout@example.com",
            password="pw12345!",
        )
        self.client.force_authenticate(self.user)
        ensure_user_subscription(self.user)

    def test_checkout_returns_session_url_in_dev_mode(self):
        response = self.client.post(
            reverse("subscriptions-checkout"),
            {"plan_id": "professional"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn("checkout_url", response.data)
        self.assertEqual(response.data["plan_id"], "professional")
        self.assertTrue(response.data.get("dev_mode"))

    def test_webhook_checkout_completed_activates_plan(self):
        webhook = self.client.post(
            reverse("stripe-webhook"),
            data=json.dumps(
                {
                    "type": "checkout.session.completed",
                    "data": {
                        "object": {
                            "client_reference_id": str(self.user.id),
                            "metadata": {"plan_id": "personal_premium"},
                        }
                    },
                }
            ),
            content_type="application/json",
        )
        self.assertEqual(webhook.status_code, status.HTTP_200_OK)
        self.user.subscription.refresh_from_db()
        self.assertEqual(self.user.subscription.plan_id, "personal_premium")
        self.assertEqual(self.user.subscription.status, UserSubscription.Status.ACTIVE)


class FreeTierListLimitTests(APITestCase):
    """TC-9.3: free-tier owned-list cap is enforced."""

    def setUp(self):
        self.user = User.objects.create_user(
            username="limit@example.com",
            email="limit@example.com",
            password="pw12345!",
        )
        self.client.force_authenticate(self.user)
        ensure_user_subscription(self.user)
        self.url = reverse("lists-list")

    def test_free_user_can_create_up_to_three_lists(self):
        for index in range(3):
            response = self.client.post(
                self.url,
                {"title": f"List {index}", "category": ListCategory.GROCERIES},
                format="json",
            )
            self.assertEqual(response.status_code, status.HTTP_201_CREATED)

    def test_fourth_owned_list_is_rejected(self):
        for index in range(3):
            ShoppingList.objects.create(
                owner=self.user,
                title=f"Existing {index}",
                category=ListCategory.GROCERIES,
            )
        response = self.client.post(
            self.url,
            {"title": "One too many", "category": ListCategory.GROCERIES},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)


class SubscriptionPaymentFailureTests(APITestCase):
    """TC-9.4: failed or expired payment downgrades access."""

    def setUp(self):
        self.user = User.objects.create_user(
            username="billing@example.com",
            email="billing@example.com",
            password="pw12345!",
        )
        self.client.force_authenticate(self.user)
        ensure_user_subscription(self.user)
        self.user.subscription.plan_id = "professional"
        self.user.subscription.stripe_subscription_id = "sub_test_123"
        self.user.subscription.save()

    def test_payment_failed_downgrades_to_free(self):
        response = self.client.post(
            reverse("stripe-webhook"),
            data=json.dumps(
                {
                    "type": "invoice.payment_failed",
                    "data": {"object": {"subscription": "sub_test_123"}},
                }
            ),
            content_type="application/json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.user.subscription.refresh_from_db()
        self.assertEqual(self.user.subscription.plan_id, "free")
        self.assertFalse(user_has_feature(self.user, "scale_lists"))

    def test_subscription_deleted_downgrades_to_free(self):
        response = self.client.post(
            reverse("stripe-webhook"),
            data=json.dumps(
                {
                    "type": "customer.subscription.deleted",
                    "data": {"object": {"id": "sub_test_123"}},
                }
            ),
            content_type="application/json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.user.subscription.refresh_from_db()
        self.assertEqual(self.user.subscription.plan_id, "free")
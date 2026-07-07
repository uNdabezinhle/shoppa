"""TC-10.1–TC-10.5: house ads, ads_free suppression, frequency capping."""
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from apps.subscriptions.services import activate_subscription, ensure_user_subscription
from apps.users.models import User

from .models import AdFormat, AdImpression
from .services import ensure_house_ads_seeded


class AdPlacementTests(APITestCase):
    """TC-10.1 / TC-10.4: placements respect subscription tier."""

    def setUp(self):
        self.free_user = User.objects.create_user(
            username="free@example.com",
            email="free@example.com",
            password="pw12345!",
        )
        self.premium_user = User.objects.create_user(
            username="premium@example.com",
            email="premium@example.com",
            password="pw12345!",
        )
        ensure_user_subscription(self.free_user)
        ensure_user_subscription(self.premium_user)
        activate_subscription(self.premium_user, "personal_premium")
        ensure_house_ads_seeded()
        self.url = reverse("ads-placements")

    def test_free_user_sees_home_banner(self):
        self.client.force_authenticate(self.free_user)
        response = self.client.get(self.url, {"surface": "home", "ad_format": "banner"})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(response.data["ads_free"])
        self.assertGreaterEqual(len(response.data["results"]), 1)
        self.assertEqual(response.data["results"][0]["ad_format"], "banner")

    def test_free_user_sees_list_banner(self):
        self.client.force_authenticate(self.free_user)
        response = self.client.get(self.url, {"surface": "list", "ad_format": "banner"})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertGreaterEqual(len(response.data["results"]), 1)

    def test_ads_free_user_gets_empty_placements(self):
        self.client.force_authenticate(self.premium_user)
        response = self.client.get(self.url, {"surface": "home"})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data["ads_free"])
        self.assertEqual(response.data["results"], [])


class AdNativePlacementTests(APITestCase):
    """TC-10.2: native/sponsored placements for comparison surfaces."""

    def setUp(self):
        self.user = User.objects.create_user(
            username="native@example.com",
            email="native@example.com",
            password="pw12345!",
        )
        ensure_user_subscription(self.user)
        ensure_house_ads_seeded()
        self.client.force_authenticate(self.user)
        self.url = reverse("ads-placements")

    def test_native_placement_available_on_list_surface(self):
        response = self.client.get(self.url, {"surface": "list", "ad_format": "native"})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertGreaterEqual(len(response.data["results"]), 1)
        self.assertIsNotNone(response.data["results"][0]["sponsor_name"])


class AdFrequencyCapTests(APITestCase):
    """TC-10.5: interstitial/rewarded capped per session."""

    def setUp(self):
        self.user = User.objects.create_user(
            username="cap@example.com",
            email="cap@example.com",
            password="pw12345!",
        )
        ensure_user_subscription(self.user)
        ensure_house_ads_seeded()
        self.client.force_authenticate(self.user)
        self.placements_url = reverse("ads-placements")
        self.impressions_url = reverse("ads-impressions")

    def test_second_interstitial_in_same_session_is_suppressed(self):
        session_key = "shop-session-1"
        first = self.client.get(
            self.placements_url,
            {
                "surface": "checkout",
                "ad_format": "interstitial",
                "session_key": session_key,
            },
        )
        placement_id = first.data["results"][0]["id"]
        recorded = self.client.post(
            self.impressions_url,
            {
                "placement_id": placement_id,
                "surface": "checkout",
                "ad_format": "interstitial",
                "session_key": session_key,
            },
            format="json",
        )
        self.assertEqual(recorded.status_code, status.HTTP_201_CREATED)

        second_fetch = self.client.get(
            self.placements_url,
            {
                "surface": "checkout",
                "ad_format": "interstitial",
                "session_key": session_key,
            },
        )
        self.assertEqual(second_fetch.data["results"], [])

        duplicate = self.client.post(
            self.impressions_url,
            {
                "placement_id": placement_id,
                "surface": "checkout",
                "ad_format": "interstitial",
                "session_key": session_key,
            },
            format="json",
        )
        self.assertEqual(duplicate.data["recorded"], False)
        self.assertEqual(duplicate.data["reason"], "frequency_cap")
        self.assertEqual(
            AdImpression.objects.filter(
                user=self.user,
                ad_format=AdFormat.INTERSTITIAL,
                session_key=session_key,
            ).count(),
            1,
        )


class AdTrackingNoOpTests(APITestCase):
    """Impression/click endpoints no-op for ads_free users."""

    def setUp(self):
        self.user = User.objects.create_user(
            username="paid@example.com",
            email="paid@example.com",
            password="pw12345!",
        )
        ensure_user_subscription(self.user)
        activate_subscription(self.user, "personal_premium")
        ensure_house_ads_seeded()
        self.client.force_authenticate(self.user)
        from .models import AdPlacement

        placement = AdPlacement.objects.filter(surface="home").first()
        self.assertIsNotNone(placement)
        self.placement_id = str(placement.id)

    def test_impression_noop_for_ads_free(self):
        response = self.client.post(
            reverse("ads-impressions"),
            {
                "placement_id": self.placement_id,
                "surface": "home",
                "ad_format": "banner",
            },
            format="json",
        )
        self.assertEqual(response.data["recorded"], False)
        self.assertEqual(response.data["reason"], "ads_free")
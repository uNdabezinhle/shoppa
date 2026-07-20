"""M7 platform endpoints — health, readiness, launch meta."""
from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient


class PlatformHealthTests(TestCase):
    def setUp(self):
        self.client = APIClient()

    def test_liveness_returns_ok(self):
        response = self.client.get(reverse("health"))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["status"], "ok")

    def test_readiness_returns_ready(self):
        response = self.client.get(reverse("health-ready"))
        self.assertEqual(response.status_code, 200)
        payload = getattr(response, "data", None) or response.json()
        self.assertEqual(payload["status"], "ready")

    def test_launch_meta_lists_milestones(self):
        response = self.client.get(reverse("meta-launch"))
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.data["launch_ready"])
        self.assertIn("m6-ads", response.data["milestones_complete"])
        self.assertIn("m7-launch", response.data["milestones_complete"])
        self.assertIn("m8-data-intelligence", response.data["milestones_complete"])
        self.assertTrue(response.data["features"].get("seed_scraper"))
        self.assertTrue(response.data["features"].get("confidence_ui"))

    def test_correlation_id_header_on_response(self):
        response = self.client.get(
            reverse("health"),
            HTTP_X_CORRELATION_ID="test-corr-123",
        )
        self.assertEqual(response["X-Correlation-ID"], "test-corr-123")
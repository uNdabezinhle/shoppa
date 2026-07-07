import json

from django.test import TestCase
from rest_framework.test import APIClient


class StripeWebhookTests(TestCase):
    def setUp(self):
        self.client = APIClient()

    def test_accepts_valid_json_payload(self):
        response = self.client.post(
            "/v1/webhooks/stripe",
            data=json.dumps({"type": "checkout.session.completed", "id": "evt_1"}),
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["received"])
        self.assertEqual(response.json()["type"], "checkout.session.completed")

    def test_rejects_invalid_json(self):
        response = self.client.post(
            "/v1/webhooks/stripe",
            data="not-json",
            content_type="application/json",
        )
        self.assertEqual(response.status_code, 400)
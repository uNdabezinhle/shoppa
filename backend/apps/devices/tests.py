from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from apps.users.models import User

from .models import Device
from .tasks import send_fcm_price_drop


class DeviceRegisterTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username="device@example.com",
            email="device@example.com",
            password="test-pass-123!",
        )
        self.client.force_authenticate(self.user)

    def test_register_device_token(self):
        response = self.client.post(
            reverse("devices-register"),
            {"token": "fcm-token-abc", "platform": "android"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertTrue(
            Device.objects.filter(user=self.user, token="fcm-token-abc").exists()
        )

    def test_reregister_updates_platform(self):
        Device.objects.create(user=self.user, token="same", platform="android")
        response = self.client.post(
            reverse("devices-register"),
            {"token": "same", "platform": "ios"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(Device.objects.filter(user=self.user).count(), 1)
        self.assertEqual(Device.objects.get(token="same").platform, "ios")


class FcmTaskTests(APITestCase):
    def test_fcm_noops_without_server_key(self):
        result = send_fcm_price_drop(
            user_ids=["00000000-0000-0000-0000-000000000001"],
            title="Drop",
            body="Body",
        )
        self.assertEqual(result["sent"], 0)
        self.assertEqual(result["skipped"], "no_fcm_key")

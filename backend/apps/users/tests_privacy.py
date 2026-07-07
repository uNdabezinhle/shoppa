"""POPIA data export and account erasure tests."""
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from apps.lists.models import ListCategory, ShoppingList
from apps.subscriptions.services import ensure_user_subscription

from .models import User


class PrivacyDataExportTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username="privacy@example.com",
            email="privacy@example.com",
            password="pw12345!",
        )
        ensure_user_subscription(self.user)
        ShoppingList.objects.create(
            owner=self.user,
            title="My groceries",
            category=ListCategory.GROCERIES,
        )
        self.client.force_authenticate(self.user)
        self.url = reverse("users-data-export")

    def test_export_includes_profile_and_lists(self):
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["user"]["email"], "privacy@example.com")
        self.assertEqual(len(response.data["owned_lists"]), 1)
        self.assertEqual(response.data["export_format"], "shoppa-user-export-v1")


class PrivacyAccountDeleteTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username="delete@example.com",
            email="delete@example.com",
            password="pw12345!",
        )
        self.user_id = self.user.id
        self.client.force_authenticate(self.user)
        self.url = reverse("users-delete-account")

    def test_delete_requires_password(self):
        response = self.client.post(self.url, {}, format="json")
        self.assertEqual(response.status_code, status.HTTP_422_UNPROCESSABLE_ENTITY)

    def test_wrong_password_is_rejected(self):
        response = self.client.post(
            self.url, {"password": "wrong"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
        self.assertTrue(User.objects.filter(pk=self.user_id).exists())

    def test_valid_password_deletes_account(self):
        response = self.client.post(
            self.url, {"password": "pw12345!"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertFalse(User.objects.filter(pk=self.user_id).exists())
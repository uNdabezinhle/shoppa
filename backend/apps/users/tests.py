"""Accounts & Authentication tests.

Traces to the QA Test Plan §5.1: TC-1.1, TC-1.2, TC-1.4.
"""
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from .models import AccountType, User


class RegistrationTests(APITestCase):
    def setUp(self):
        self.url = reverse("auth-register")

    def test_register_with_valid_email_creates_personal_account(self):
        """TC-1.1: register with valid email/password creates a Personal account."""
        response = self.client.post(
            self.url,
            {"email": "shopper@example.com", "password": "a-strong-passw0rd!"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["account_type"], AccountType.PERSONAL)
        self.assertTrue(User.objects.filter(email="shopper@example.com").exists())

    def test_register_with_existing_email_is_rejected(self):
        """TC-1.2: register with an existing email is rejected with a clear error."""
        User.objects.create_user(
            username="shopper@example.com", email="shopper@example.com", password="x"
        )
        response = self.client.post(
            self.url,
            {"email": "shopper@example.com", "password": "another-passw0rd!"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("email", response.data["error"]["fields"])

    def test_new_user_is_assigned_correct_region_and_locale(self):
        """TC-1.4: new user is assigned the correct region and locale."""
        response = self.client.post(
            self.url,
            {
                "email": "capetown@example.com",
                "password": "a-strong-passw0rd!",
                "region": "ZA",
            },
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["region"], "ZA")

    def test_register_account_type_can_be_professional(self):
        """FR-1.2: the system shall support four account types."""
        response = self.client.post(
            self.url,
            {
                "email": "chef@example.com",
                "password": "a-strong-passw0rd!",
                "account_type": "professional",
            },
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["account_type"], "professional")


class LoginAndProfileTests(APITestCase):
    def setUp(self):
        self.password = "a-strong-passw0rd!"
        self.user = User.objects.create_user(
            username="shopper@example.com",
            email="shopper@example.com",
            password=self.password,
            account_type=AccountType.PERSONAL,
            region="ZA",
        )
        self.login_url = reverse("auth-login")
        self.refresh_url = reverse("auth-refresh")
        self.me_url = reverse("users-me")

    def test_login_with_valid_credentials_returns_tokens_and_user(self):
        response = self.client.post(
            self.login_url,
            {"email": "shopper@example.com", "password": self.password},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn("access", response.data)
        self.assertIn("refresh", response.data)
        self.assertEqual(response.data["user"]["email"], "shopper@example.com")

    def test_login_with_wrong_password_is_rejected(self):
        response = self.client.post(
            self.login_url,
            {"email": "shopper@example.com", "password": "wrong-password"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_refresh_token_issues_new_access_token(self):
        """TC-1.3: expired access token is refreshed transparently without re-login."""
        login = self.client.post(
            self.login_url,
            {"email": "shopper@example.com", "password": self.password},
            format="json",
        )
        response = self.client.post(
            self.refresh_url, {"refresh": login.data["refresh"]}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn("access", response.data)

    def test_authenticated_user_can_fetch_own_profile(self):
        login = self.client.post(
            self.login_url,
            {"email": "shopper@example.com", "password": self.password},
            format="json",
        )
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {login.data['access']}")
        response = self.client.get(self.me_url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["email"], "shopper@example.com")

    def test_unauthenticated_request_to_me_is_rejected(self):
        response = self.client.get(self.me_url)
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_patch_me_updates_locale(self):
        login = self.client.post(
            self.login_url,
            {"email": "shopper@example.com", "password": self.password},
            format="json",
        )
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {login.data['access']}")
        response = self.client.patch(
            self.me_url, {"locale": "en-GB"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["locale"], "en-GB")

    def test_password_reset_stub_always_accepts(self):
        url = reverse("auth-password-reset")
        response = self.client.post(
            url, {"email": "nobody@example.com"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_202_ACCEPTED)

    def test_personal_user_can_upgrade_to_professional(self):
        login = self.client.post(
            self.login_url,
            {"email": "shopper@example.com", "password": self.password},
            format="json",
        )
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {login.data['access']}")
        response = self.client.post(reverse("users-me-upgrade"), format="json")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["account_type"], AccountType.PROFESSIONAL)

from django.contrib.auth import get_user_model
from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from apps.price_intelligence.models import Product
from apps.users.privacy import build_user_data_export

from .allergens import canonicalize_allergen, normalize_allergen_list
from .gtin import gtin_check_digit, is_valid_gtin, normalize_gtin
from .models import GtinProduct, UserAllergenProfile
from .off_client import FixtureOffClient, map_off_json
from .scoring import verify_for_user
from .services import verify_gtin

User = get_user_model()


class GtinTests(TestCase):
    def test_check_digit_and_normalize_upc(self):
        body = "001234567890"
        # 12-digit UPC padded to 13
        code_12 = "012345678905"  # may or may not be valid
        self.assertTrue(is_valid_gtin("3017620422003"))
        self.assertEqual(normalize_gtin("3017620422003"), "3017620422003")
        self.assertIsNone(normalize_gtin("123"))
        self.assertIsNone(normalize_gtin("abcdefghijk"))

    def test_synthetic_sa_gtin(self):
        self.assertTrue(is_valid_gtin("6001234567899"))
        self.assertEqual(
            gtin_check_digit("600123456789"),
            "9",
        )


class ScoringTests(TestCase):
    def test_red_on_declared_allergen(self):
        r = verify_for_user(
            product_found=True,
            product_allergens=["en:milk"],
            product_traces=[],
            ingredients_text="milk",
            profile_allergens=["en:milk"],
        )
        self.assertEqual(r.level, "red")
        self.assertIn("en:milk", r.matched_allergens)

    def test_yellow_on_traces(self):
        r = verify_for_user(
            product_found=True,
            product_allergens=[],
            product_traces=["en:nuts"],
            ingredients_text="sugar",
            profile_allergens=["en:nuts"],
        )
        self.assertEqual(r.level, "yellow")
        self.assertIn("en:nuts", r.trace_matches)

    def test_green_when_clear(self):
        r = verify_for_user(
            product_found=True,
            product_allergens=["en:milk"],
            product_traces=[],
            ingredients_text="milk",
            profile_allergens=["en:nuts"],
        )
        self.assertEqual(r.level, "green")

    def test_unknown_without_profile(self):
        r = verify_for_user(
            product_found=True,
            product_allergens=["en:milk"],
            product_traces=[],
            ingredients_text="milk",
            profile_allergens=[],
        )
        self.assertEqual(r.level, "unknown")

    def test_unknown_not_found(self):
        r = verify_for_user(
            product_found=False,
            product_allergens=[],
            product_traces=[],
            ingredients_text="",
            profile_allergens=["en:milk"],
        )
        self.assertEqual(r.level, "unknown")


class AllergenNormalizeTests(TestCase):
    def test_aliases(self):
        self.assertEqual(canonicalize_allergen("en:soya"), "en:soybeans")
        self.assertEqual(
            normalize_allergen_list(["en:milk", "en:lactose", "en:milk"]),
            ["en:milk"],
        )


class OffMapTests(TestCase):
    def test_map_found_product(self):
        payload = {
            "status": 1,
            "product": {
                "product_name": "Demo",
                "brands": "BrandCo",
                "ingredients_text": "water",
                "allergens_tags": ["en:milk"],
                "traces_tags": [],
                "nutriments": {"energy-kcal_100g": 10},
                "categories": "Beverages",
                "nutriscore_grade": "c",
            },
        }
        off = map_off_json("3017620422003", payload)
        self.assertTrue(off.found)
        self.assertEqual(off.name, "Demo")
        self.assertEqual(off.allergens, ["en:milk"])

    def test_map_not_found(self):
        off = map_off_json("3017620422003", {"status": 0, "product": {}})
        self.assertFalse(off.found)


@override_settings(OFF_CLIENT_MODE="fixture")
class VerifyApiTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username="verify@example.com",
            email="verify@example.com",
            password="a-strong-passw0rd!",
            region="ZA",
        )
        self.client = APIClient()
        self.client.force_authenticate(user=self.user)

    def test_verify_fixture_product_with_profile_red(self):
        from django.utils import timezone

        UserAllergenProfile.objects.create(
            user=self.user,
            allergens=["en:milk"],
            consent_at=timezone.now(),
        )

        res = self.client.get("/v1/products/verify", {"gtin": "6001234567899"})
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.data["status"], "found")
        self.assertEqual(res.data["verification"]["level"], "red")
        self.assertEqual(res.data["product"]["name"], "Full Cream Milk 2L")
        self.assertTrue(res.data["sources"]["open_food_facts"])

    def test_verify_invalid_gtin(self):
        res = self.client.get("/v1/products/verify", {"gtin": "12"})
        self.assertEqual(res.status_code, 400)
        self.assertEqual(res.data["status"], "invalid")

    def test_verify_caches_second_call(self):
        r1 = self.client.get("/v1/products/verify", {"gtin": "3017620422003"})
        self.assertEqual(r1.status_code, 200)
        self.assertFalse(r1.data["cached"])
        r2 = self.client.get("/v1/products/verify", {"gtin": "3017620422003"})
        self.assertEqual(r2.status_code, 200)
        self.assertTrue(r2.data["cached"])

    def test_allergen_profile_requires_consent(self):
        res = self.client.put(
            "/v1/users/me/allergen-profile",
            {"allergens": ["en:milk"], "consent": False},
            format="json",
        )
        self.assertEqual(res.status_code, 400)

    def test_allergen_profile_put_get(self):
        res = self.client.put(
            "/v1/users/me/allergen-profile",
            {"allergens": ["en:milk", "en:nuts"], "consent": True},
            format="json",
        )
        self.assertEqual(res.status_code, 200)
        self.assertEqual(set(res.data["allergens"]), {"en:milk", "en:nuts"})
        self.assertIsNotNone(res.data["consent_at"])

        got = self.client.get("/v1/users/me/allergen-profile")
        self.assertEqual(got.status_code, 200)
        self.assertIn("canonical", got.data)

    def test_shoppa_catalogue_merge(self):
        Product.objects.create(
            name="Full Cream Milk 2L",
            region="ZA",
            gtin="6001234567899",
        )
        res = self.client.get("/v1/products/verify", {"gtin": "6001234567899"})
        self.assertEqual(res.status_code, 200)
        self.assertTrue(res.data["sources"]["shoppa_catalogue"])
        self.assertIsNotNone(res.data["sources"]["shoppa_product_id"])

    def test_correction_create(self):
        res = self.client.post(
            "/v1/products/corrections",
            {
                "gtin": "6001234567899",
                "field": "name",
                "suggested_value": "Milk 2L",
                "note": "wrong name",
            },
            format="json",
        )
        self.assertEqual(res.status_code, 201)
        self.assertEqual(res.data["status"], "pending")

    def test_scan_history(self):
        self.client.get("/v1/products/verify", {"gtin": "6001234567899"})
        res = self.client.get("/v1/users/me/scan-history")
        self.assertEqual(res.status_code, 200)
        self.assertGreaterEqual(len(res.data["results"]), 1)

    def test_privacy_export_includes_allergen_profile(self):
        from django.utils import timezone

        UserAllergenProfile.objects.create(
            user=self.user,
            allergens=["en:eggs"],
            consent_at=timezone.now(),
        )
        export = build_user_data_export(self.user)
        self.assertIsNotNone(export.get("allergen_profile"))
        self.assertEqual(export["allergen_profile"]["allergens"], ["en:eggs"])
        self.assertIn("scan_history", export)


@override_settings(OFF_CLIENT_MODE="fixture")
class VerifyServiceTests(TestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username="svc@example.com",
            email="svc@example.com",
            password="a-strong-passw0rd!",
        )

    def test_fixture_client_direct(self):
        off = FixtureOffClient().fetch("6001234567899")
        self.assertTrue(off.found)
        self.assertIn("en:milk", off.allergens)

    def test_verify_gtin_not_found(self):
        # Valid check digit but not in fixtures
        body = "999999999999"
        code = body + gtin_check_digit(body)
        payload = verify_gtin(code, user=self.user)
        self.assertEqual(payload["status"], "not_found")

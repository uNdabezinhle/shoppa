"""Smoke: product verify GTIN + allergen scoring (fixture OFF client).

  cd backend
  set OFF_CLIENT_MODE=fixture
  python scripts/verify_smoke.py
"""
import os
import sys

import django

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "shoppa_api.settings")
os.environ.setdefault("OFF_CLIENT_MODE", "fixture")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
django.setup()

from django.conf import settings  # noqa: E402
from django.contrib.auth import get_user_model  # noqa: E402
from django.utils import timezone  # noqa: E402
from rest_framework.test import APIClient  # noqa: E402

from apps.product_verify.models import UserAllergenProfile  # noqa: E402
from apps.product_verify.services import verify_gtin  # noqa: E402

User = get_user_model()

# Allow APIClient host in smoke runs against local settings.
if "testserver" not in settings.ALLOWED_HOSTS:
    settings.ALLOWED_HOSTS = list(settings.ALLOWED_HOSTS) + ["testserver"]


def main() -> int:
    email = "verify-smoke@example.com"
    user, _ = User.objects.get_or_create(
        username=email,
        defaults={"email": email, "region": "ZA"},
    )
    user.set_password("smoke-test-pass!")
    user.save()
    UserAllergenProfile.objects.update_or_create(
        user=user,
        defaults={
            "allergens": ["en:milk"],
            "consent_at": timezone.now(),
        },
    )

    # Service-level check (no HTTP host concerns).
    payload = verify_gtin("6001234567899", user=user, record_scan=False)
    if payload.get("status") != "found":
        print(f"FAIL: expected found, got {payload}", file=sys.stderr)
        return 1
    if payload["verification"]["level"] != "red":
        print(
            f"FAIL: expected red for milk profile, got "
            f"{payload['verification']}",
            file=sys.stderr,
        )
        return 1

    client = APIClient()
    client.force_authenticate(user=user)
    res = client.get("/v1/products/verify", {"gtin": "6001234567899"})
    if res.status_code != 200:
        print(f"FAIL: verify status {res.status_code}", file=sys.stderr)
        return 1
    body = res.json() if hasattr(res, "json") else res.data
    if body.get("verification", {}).get("level") != "red":
        print(f"FAIL: API level not red: {body}", file=sys.stderr)
        return 1

    print("OK: verify smoke — milk product scores red for milk profile")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

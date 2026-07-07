#!/usr/bin/env python
"""M6 gate smoke test — house ads, ads_free suppression, Docker-ready stack.

Usage (from backend/):
    python scripts/m6_smoke.py
"""
from __future__ import annotations

import os
import sys
import uuid
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "shoppa_api.settings")
_hosts = os.environ.get("ALLOWED_HOSTS", "localhost,127.0.0.1")
if "testserver" not in _hosts:
    os.environ["ALLOWED_HOSTS"] = f"{_hosts},testserver"

import django  # noqa: E402

django.setup()

from django.urls import reverse  # noqa: E402
from rest_framework.test import APIClient  # noqa: E402

from apps.ads.services import ensure_house_ads_seeded  # noqa: E402
from apps.subscriptions.services import (  # noqa: E402
    activate_subscription,
    ensure_user_subscription,
)
from apps.users.models import User  # noqa: E402


def main() -> int:
    ensure_house_ads_seeded()

    free_user, _ = User.objects.get_or_create(
        username="m6-free@example.com",
        defaults={"email": "m6-free@example.com", "region": "ZA"},
    )
    free_user.set_password("smoke-test-pass!")
    free_user.save()
    ensure_user_subscription(free_user)

    premium_user, _ = User.objects.get_or_create(
        username="m6-premium@example.com",
        defaults={"email": "m6-premium@example.com", "region": "ZA"},
    )
    premium_user.set_password("smoke-test-pass!")
    premium_user.save()
    ensure_user_subscription(premium_user)
    activate_subscription(premium_user, "personal_premium")

    client = APIClient()
    client.force_authenticate(free_user)

    home = client.get(
        reverse("ads-placements"),
        {"surface": "home", "ad_format": "banner"},
    )
    if home.status_code != 200 or not home.data["results"]:
        print("FAIL: free user should see home banner", file=sys.stderr)
        return 1

    list_banner = client.get(
        reverse("ads-placements"),
        {"surface": "list", "ad_format": "banner"},
    )
    if list_banner.status_code != 200 or not list_banner.data["results"]:
        print("FAIL: free user should see list banner", file=sys.stderr)
        return 1

    native = client.get(
        reverse("ads-placements"),
        {"surface": "list", "ad_format": "native"},
    )
    if native.status_code != 200 or not native.data["results"]:
        print("FAIL: native placement missing for comparison surface", file=sys.stderr)
        return 1

    placement_id = home.data["results"][0]["id"]
    impression = client.post(
        reverse("ads-impressions"),
        {
            "placement_id": placement_id,
            "surface": "home",
            "ad_format": "banner",
        },
        format="json",
    )
    if impression.status_code != 201 or not impression.data.get("recorded"):
        print("FAIL: impression not recorded", file=sys.stderr)
        return 1

    session_key = f"m6-smoke-{uuid.uuid4().hex[:12]}"
    interstitial = client.get(
        reverse("ads-placements"),
        {
            "surface": "checkout",
            "ad_format": "interstitial",
            "session_key": session_key,
        },
    )
    if not interstitial.data["results"]:
        print("FAIL: checkout interstitial missing", file=sys.stderr)
        return 1
    interstitial_id = interstitial.data["results"][0]["id"]
    client.post(
        reverse("ads-impressions"),
        {
            "placement_id": interstitial_id,
            "surface": "checkout",
            "ad_format": "interstitial",
            "session_key": session_key,
        },
        format="json",
    )
    capped = client.get(
        reverse("ads-placements"),
        {
            "surface": "checkout",
            "ad_format": "interstitial",
            "session_key": session_key,
        },
    )
    if capped.data["results"]:
        print("FAIL: interstitial should be frequency-capped", file=sys.stderr)
        return 1

    client.force_authenticate(premium_user)
    paid = client.get(reverse("ads-placements"), {"surface": "home"})
    if paid.status_code != 200 or paid.data["results"]:
        print("FAIL: ads_free user should see no placements", file=sys.stderr)
        return 1
    if not paid.data["ads_free"]:
        print("FAIL: premium response should flag ads_free", file=sys.stderr)
        return 1

    print(
        "M6 smoke OK: banners + native + impressions + frequency cap + ads_free"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
#!/usr/bin/env python
"""M5 gate smoke test — subscription plans, checkout, free-tier limits.

Usage (from backend/):
    python scripts/m5_smoke.py
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "shoppa_api.settings")

import django  # noqa: E402

django.setup()

from django.urls import reverse  # noqa: E402
from rest_framework.test import APIClient  # noqa: E402

from apps.lists.models import ListCategory, ShoppingList  # noqa: E402
from apps.subscriptions.services import ensure_plans_seeded, ensure_user_subscription  # noqa: E402
from apps.users.models import User  # noqa: E402


def main() -> int:
    ensure_plans_seeded()

    user, _ = User.objects.get_or_create(
        username="m5-smoke@example.com",
        defaults={"email": "m5-smoke@example.com", "region": "ZA"},
    )
    user.set_password("smoke-test-pass!")
    user.save()
    ensure_user_subscription(user)

    client = APIClient()
    client.force_authenticate(user)

    plans = client.get(reverse("subscriptions-plans"))
    if plans.status_code != 200 or len(plans.data["results"]) < 3:
        print("FAIL: expected subscription plans", file=sys.stderr)
        return 1

    me = client.get(reverse("subscriptions-me"))
    if me.status_code != 200 or me.data["plan"]["slug"] != "free":
        print("FAIL: expected free subscription by default", file=sys.stderr)
        return 1

    checkout = client.post(
        reverse("subscriptions-checkout"),
        {"plan_id": "professional"},
        format="json",
    )
    if checkout.status_code != 200 or "checkout_url" not in checkout.data:
        print("FAIL: checkout session missing", file=sys.stderr)
        return 1

    ShoppingList.objects.filter(owner=user).delete()
    for index in range(3):
        ShoppingList.objects.create(
            owner=user, title=f"Smoke {index}", category=ListCategory.GROCERIES
        )
    blocked = client.post(
        reverse("lists-list"),
        {"title": "Over limit", "category": ListCategory.GROCERIES},
        format="json",
    )
    if blocked.status_code != 403:
        print("FAIL: fourth list should be forbidden on free tier", file=sys.stderr)
        return 1

    webhook = client.post(
        reverse("stripe-webhook"),
        data=json.dumps(
            {
                "type": "checkout.session.completed",
                "data": {
                    "object": {
                        "client_reference_id": str(user.id),
                        "metadata": {"plan_id": "professional"},
                    }
                },
            }
        ),
        content_type="application/json",
    )
    if webhook.status_code != 200:
        print("FAIL: webhook did not accept checkout completion", file=sys.stderr)
        return 1

    me_after = client.get(reverse("subscriptions-me"))
    if me_after.data["plan"]["slug"] != "professional":
        print("FAIL: professional plan not activated after webhook", file=sys.stderr)
        return 1

    print(
        "M5 smoke OK: "
        f"{len(plans.data['results'])} plans, free limit enforced, "
        f"checkout + webhook activated {me_after.data['plan']['slug']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
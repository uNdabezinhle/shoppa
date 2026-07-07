#!/usr/bin/env python
"""M5 gate smoke test — subscriptions, admin console, export, downgrade.

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
_hosts = os.environ.get("ALLOWED_HOSTS", "localhost,127.0.0.1")
if "testserver" not in _hosts:
    os.environ["ALLOWED_HOSTS"] = f"{_hosts},testserver"

import django  # noqa: E402

django.setup()

from django.urls import reverse  # noqa: E402
from rest_framework.test import APIClient  # noqa: E402

from apps.lists.models import ListCategory, ListItem, ShoppingList  # noqa: E402
from apps.subscriptions.services import (  # noqa: E402
    downgrade_to_free,
    ensure_plans_seeded,
    ensure_user_subscription,
)
from apps.users.models import AccountType, User  # noqa: E402


def main() -> int:
    ensure_plans_seeded()

    user, _ = User.objects.get_or_create(
        username="m5-smoke@example.com",
        defaults={"email": "m5-smoke@example.com", "region": "ZA"},
    )
    user.set_password("smoke-test-pass!")
    user.save()
    ensure_user_subscription(user)
    downgrade_to_free(user)
    ShoppingList.objects.filter(owner=user).delete()

    admin, _ = User.objects.get_or_create(
        username="m5-admin@example.com",
        defaults={
            "email": "m5-admin@example.com",
            "region": "ZA",
            "account_type": AccountType.ADMIN,
        },
    )
    admin.account_type = AccountType.ADMIN
    admin.set_password("smoke-test-pass!")
    admin.save()

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

    user.subscription.stripe_subscription_id = "sub_m5_smoke"
    user.subscription.save(update_fields=["stripe_subscription_id"])

    downgrade = client.post(
        reverse("stripe-webhook"),
        data=json.dumps(
            {
                "type": "invoice.payment_failed",
                "data": {"object": {"subscription": "sub_m5_smoke"}},
            }
        ),
        content_type="application/json",
    )
    if downgrade.status_code != 200:
        print("FAIL: payment_failed webhook rejected", file=sys.stderr)
        return 1
    user.subscription.refresh_from_db()
    if user.subscription.plan_id != "free":
        print("FAIL: payment failure should downgrade to free", file=sys.stderr)
        return 1

    export_list = ShoppingList.objects.create(
        owner=user, title="Export smoke", category=ListCategory.GROCERIES
    )
    ListItem.objects.create(list=export_list, name="Bread", quantity=1, unit="ea")
    export = client.get(
        reverse("lists-export", kwargs={"pk": export_list.id}),
        {"type": "csv"},
    )
    if export.status_code != 200 or b"Bread" not in export.content:
        print("FAIL: CSV export missing item rows", file=sys.stderr)
        return 1

    admin_client = APIClient()
    admin_client.force_authenticate(admin)
    overview = admin_client.get(reverse("admin-overview"))
    if overview.status_code != 200 or "users" not in overview.data:
        print("FAIL: admin overview unavailable", file=sys.stderr)
        return 1

    admin_client.force_authenticate(user)
    denied = admin_client.get(reverse("admin-overview"))
    if denied.status_code != 403:
        print("FAIL: non-admin should not access overview", file=sys.stderr)
        return 1

    print(
        "M5 smoke OK: "
        f"{len(plans.data['results'])} plans, free limit enforced, "
        f"checkout + downgrade, export + admin overview"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
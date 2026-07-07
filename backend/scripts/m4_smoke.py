#!/usr/bin/env python
"""M4 gate smoke test — delivery quotes for a catalogue-linked list.

Usage (from backend/):
    python scripts/m4_smoke.py

Requires seed_launch_data to have been run.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "shoppa_api.settings")

import django  # noqa: E402

django.setup()

from django.core.management import call_command  # noqa: E402
from rest_framework.test import APIClient  # noqa: E402

from apps.delivery.services import get_delivery_quotes_for_list  # noqa: E402
from apps.lists.models import ListCategory, ListItem, ShoppingList  # noqa: E402
from apps.price_intelligence.models import Product  # noqa: E402
from apps.users.models import User  # noqa: E402


def main() -> int:
    call_command("seed_launch_data", verbosity=0)

    user, _ = User.objects.get_or_create(
        username="m4-smoke@example.com",
        defaults={"email": "m4-smoke@example.com", "region": "ZA"},
    )
    user.set_password("smoke-test-pass!")
    user.save()

    milk = Product.objects.get(name="Full Cream Milk 2L", region="ZA")
    bread = Product.objects.get(name="Brown Bread 700g", region="ZA")

    shopping_list, _ = ShoppingList.objects.get_or_create(
        owner=user,
        title="M4 Smoke Basket",
        defaults={"category": ListCategory.GROCERIES},
    )
    ListItem.objects.filter(list=shopping_list).delete()
    ListItem.objects.create(
        list=shopping_list, name=milk.name, product_id=milk.id, quantity=1
    )
    ListItem.objects.create(
        list=shopping_list, name=bread.name, product_id=bread.id, quantity=1
    )

    payload = get_delivery_quotes_for_list(shopping_list)
    quotes = payload.get("quotes") or []
    if len(quotes) < 4:
        print("FAIL: expected quotes from all four launch platforms", file=sys.stderr)
        return 1

    platforms = {quote["platform"] for quote in quotes}
    expected = {"checkers_6060", "pnp_asap", "spar_2u", "woolies_dash"}
    if platforms != expected:
        print(f"FAIL: unexpected platforms {platforms}", file=sys.stderr)
        return 1

    cheapest = quotes[0]
    if cheapest["total"] <= 0 or cheapest["eta_minutes"] <= 0:
        print("FAIL: cheapest quote missing price or ETA", file=sys.stderr)
        return 1
    if "aff=shoppa" not in cheapest["order_url"]:
        print("FAIL: order URL missing affiliate tracking", file=sys.stderr)
        return 1

    client = APIClient()
    client.force_authenticate(user)
    response = client.get(f"/v1/lists/{shopping_list.id}/delivery-quotes")
    if response.status_code != 200 or len(response.data["quotes"]) < 4:
        print("FAIL: delivery-quotes API returned insufficient quotes", file=sys.stderr)
        return 1

    print(
        f"M4 smoke OK: {len(quotes)} platforms, cheapest {cheapest['platform']} "
        f"total {cheapest['total']} minor units, ETA {cheapest['eta_minutes']} min"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
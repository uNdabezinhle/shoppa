#!/usr/bin/env python
"""M3 gate smoke test — catalogue-linked list shows savings and promos.

Usage (from backend/):
    python scripts/m3_smoke.py

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

from apps.lists.models import ListCategory, ListItem, ShoppingList  # noqa: E402
from apps.price_intelligence.models import Product  # noqa: E402
from apps.price_intelligence.services import compare_stores_for_list  # noqa: E402
from apps.promotions.services import active_promotions_for_user  # noqa: E402
from apps.users.models import User  # noqa: E402


def main() -> int:
    call_command("seed_launch_data", verbosity=0)

    user, _ = User.objects.get_or_create(
        username="m3-smoke@example.com",
        defaults={"email": "m3-smoke@example.com", "region": "ZA"},
    )
    user.set_password("smoke-test-pass!")
    user.save()

    milk = Product.objects.get(name="Full Cream Milk 2L", region="ZA")
    bread = Product.objects.get(name="Brown Bread 700g", region="ZA")

    shopping_list, _ = ShoppingList.objects.get_or_create(
        owner=user,
        title="M3 Smoke Basket",
        defaults={"category": ListCategory.GROCERIES},
    )
    ListItem.objects.filter(list=shopping_list).delete()
    ListItem.objects.create(
        list=shopping_list, name=milk.name, product_id=milk.id, quantity=1
    )
    ListItem.objects.create(
        list=shopping_list, name=bread.name, product_id=bread.id, quantity=1
    )

    comparison = compare_stores_for_list(shopping_list)
    stores = comparison.get("stores") or []
    best = comparison.get("best") or {}
    if len(stores) < 2:
        print("FAIL: expected at least 2 comparable stores", file=sys.stderr)
        return 1
    if not best.get("saves") or best["saves"] <= 0:
        print("FAIL: expected positive best.saves", file=sys.stderr)
        return 1

    promos = active_promotions_for_user(user)
    if not promos.exists():
        print("FAIL: expected seeded promotions", file=sys.stderr)
        return 1

    client = APIClient()
    client.force_authenticate(user)
    search = client.get("/v1/products", {"q": "milk"})
    if search.status_code != 200 or not search.data["results"]:
        print("FAIL: product search returned no milk results", file=sys.stderr)
        return 1

    print(
        f"M3 smoke OK: {len(stores)} stores, saves {best['saves']} minor units, "
        f"{promos.count()} promotions, search hit '{search.data['results'][0]['name']}'"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
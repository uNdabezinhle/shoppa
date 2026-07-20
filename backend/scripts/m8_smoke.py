#!/usr/bin/env python
"""M8 data intelligence gate smoke.

Usage (from backend/):
    python scripts/m8_smoke.py

Checks: seed scraper ingest, product search, price-drop notification + FCM task,
launch meta feature flags.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path
from unittest.mock import patch

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "shoppa_api.settings")
_hosts = os.environ.get("ALLOWED_HOSTS", "localhost,127.0.0.1")
if "testserver" not in _hosts:
    os.environ["ALLOWED_HOSTS"] = f"{_hosts},testserver"

import django  # noqa: E402

django.setup()

from django.core.management import call_command  # noqa: E402
from django.urls import reverse  # noqa: E402
from rest_framework.test import APIClient  # noqa: E402

from apps.devices.models import Device  # noqa: E402
from apps.lists.models import ListCategory, ListItem, ShoppingList  # noqa: E402
from apps.notifications.models import Notification  # noqa: E402
from apps.price_intelligence.models import (  # noqa: E402
    CurrentPrice,
    PriceObservation,
    PriceSource,
    Product,
    Store,
)
from apps.price_intelligence.services import record_observation  # noqa: E402
from apps.price_intelligence.tasks import scrape_catalogue_prices  # noqa: E402
from apps.users.models import User  # noqa: E402


def main() -> int:
    call_command("seed_launch_data", verbosity=0)

    result = scrape_catalogue_prices.apply(args=["ZA"]).get()
    if not result.get("observations_ingested"):
        print("FAIL: seed scraper ingested zero observations", file=sys.stderr)
        return 1
    if result.get("mode") not in (None, "seed", "live"):
        print(f"FAIL: unexpected scraper mode {result.get('mode')}", file=sys.stderr)
        return 1

    user, _ = User.objects.get_or_create(
        username="m8-smoke@example.com",
        defaults={"email": "m8-smoke@example.com", "region": "ZA"},
    )
    user.set_password("smoke-test-pass!")
    user.save()

    client = APIClient()
    client.force_authenticate(user)

    meta = client.get(reverse("meta-launch"))
    if meta.status_code != 200:
        print("FAIL: launch meta", file=sys.stderr)
        return 1
    features = meta.data.get("features") or {}
    if not features.get("seed_scraper") or not features.get("confidence_ui"):
        print("FAIL: M8 feature flags missing on launch meta", file=sys.stderr)
        return 1
    milestones = meta.data.get("milestones_complete") or []
    if "m8-data-intelligence" not in milestones:
        print("FAIL: m8-data-intelligence not in milestones_complete", file=sys.stderr)
        return 1

    search = client.get("/v1/products", {"q": "milk"})
    if search.status_code != 200 or not search.data.get("results"):
        print("FAIL: product search returned no milk results", file=sys.stderr)
        return 1

    reg = client.post(
        reverse("devices-register"),
        {"token": "m8-smoke-token", "platform": "android"},
        format="json",
    )
    if reg.status_code not in (200, 201):
        print(f"FAIL: device register {reg.status_code}", file=sys.stderr)
        return 1
    if not Device.objects.filter(user=user, token="m8-smoke-token").exists():
        print("FAIL: device not stored", file=sys.stderr)
        return 1

    milk = Product.objects.get(name="Full Cream Milk 2L", region="ZA")
    store = Store.objects.filter(region="ZA").first()
    shopping_list, _ = ShoppingList.objects.get_or_create(
        owner=user,
        title="M8 Smoke Basket",
        defaults={"category": ListCategory.GROCERIES},
    )
    ListItem.objects.filter(list=shopping_list).delete()
    ListItem.objects.create(
        list=shopping_list, name=milk.name, product_id=milk.id, quantity=1
    )

    Notification.objects.filter(user=user).delete()
    PriceObservation.objects.filter(product=milk, store=store).delete()
    CurrentPrice.objects.filter(product=milk, store=store).delete()

    fcm_calls = []

    def _capture(*args, **kwargs):
        fcm_calls.append((args, kwargs))
        return {"sent": 0, "skipped": "mocked"}

    with patch("apps.devices.tasks.send_fcm_price_drop.delay", side_effect=_capture):
        record_observation(
            product=milk, store=store, price=4000, source=PriceSource.STORE
        )
        record_observation(
            product=milk, store=store, price=2000, source=PriceSource.STORE
        )

    if Notification.objects.filter(user=user, kind="price_drop").count() < 1:
        print("FAIL: expected price-drop notification", file=sys.stderr)
        return 1
    if not fcm_calls:
        print("FAIL: expected FCM task enqueue on price drop", file=sys.stderr)
        return 1

    print("M8 smoke OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""Seed South-Africa launch stores, catalogue, and starter prices.

Idempotent: safe to re-run in dev, CI, and staging. Prices are taken from
the interactive prototype (docs/shoppa-prototype.jsx). The M8 seed scraper
re-ingests the same catalogue via record_observation (FR-5.1 SCRAPED).
"""
from decimal import Decimal

from django.core.management.base import BaseCommand
from django.utils import timezone

from apps.ads.services import ensure_house_ads_seeded
from apps.lists.models import ListCategory
from apps.price_intelligence.models import PriceSource, Product, Store
from apps.price_intelligence.services import record_observation
from apps.promotions.models import Promotion
from apps.regions.models import Region

# Store slug -> display name (launch retailers, Architecture §7.1).
LAUNCH_STORES = {
    "checkers": "Checkers",
    "pnp": "Pick n Pay",
    "spar": "SPAR",
    "woolies": "Woolworths",
}

# Product key -> (display name, {store_slug: price_minor_units})
LAUNCH_PRODUCTS = {
    "milk": ("Full Cream Milk 2L", {
        "checkers": 3299, "pnp": 3450, "spar": 3399, "woolies": 3899,
    }),
    "bread": ("Brown Bread 700g", {
        "checkers": 1799, "pnp": 1699, "spar": 1850, "woolies": 2299,
    }),
    "eggs": ("Large Eggs ×18", {
        "checkers": 5499, "pnp": 5299, "spar": 5699, "woolies": 6499,
    }),
    "chicken": ("Chicken Breasts 1kg", {
        "checkers": 8999, "pnp": 9499, "spar": 8799, "woolies": 11999,
    }),
    "rice": ("Basmati Rice 2kg", {
        "checkers": 6499, "pnp": 6299, "spar": 6599, "woolies": 7899,
    }),
    "coffee": ("Ground Coffee 250g", {
        "checkers": 7999, "pnp": 8299, "spar": 7799, "woolies": 9499,
    }),
    "bananas": ("Bananas 1kg", {
        "checkers": 2499, "pnp": 2399, "spar": 2599, "woolies": 2999,
    }),
    "cheese": ("Cheddar Cheese 800g", {
        "checkers": 9999, "pnp": 10499, "spar": 9799, "woolies": 12999,
    }),
}

# Demo promotions for M3 E2E (FR-7.1 / FR-7.2).
LAUNCH_PROMOTIONS = [
    {
        "product_key": "milk",
        "store_slug": "checkers",
        "title": "20% off milk",
        "description": "This week at Checkers",
        "category": ListCategory.GROCERIES,
    },
    {
        "product_key": "bread",
        "store_slug": "pnp",
        "title": "Brown bread special",
        "description": "Pick n Pay bakery deal",
        "category": ListCategory.GROCERIES,
    },
]


class Command(BaseCommand):
    help = "Seed ZA region, launch stores, catalogue products, and starter prices."

    def handle(self, *args, **options):
        region, created = Region.objects.update_or_create(
            code="ZA",
            defaults={
                "name": "South Africa",
                "currency_code": "ZAR",
                "locale": "en-ZA",
                "tax_rate": Decimal("0.15"),
            },
        )
        self.stdout.write(
            self.style.SUCCESS(
                f"Region {region.code} {'created' if created else 'updated'}"
            )
        )

        stores_by_slug = {}
        for slug, name in LAUNCH_STORES.items():
            store, created = Store.objects.get_or_create(
                name=name,
                region="ZA",
                defaults={},
            )
            stores_by_slug[slug] = store
            self.stdout.write(
                f"  Store {name} {'created' if created else 'exists'}"
            )

        now = timezone.now()
        products_by_key = {}
        for key, (product_name, prices) in LAUNCH_PRODUCTS.items():
            product, created = Product.objects.get_or_create(
                name=product_name,
                region="ZA",
                defaults={},
            )
            products_by_key[key] = product
            self.stdout.write(
                f"  Product {product_name} {'created' if created else 'exists'}"
            )
            for store_slug, price in prices.items():
                store = stores_by_slug[store_slug]
                record_observation(
                    product=product,
                    store=store,
                    price=price,
                    source=PriceSource.SCRAPED,
                    observed_at=now,
                )

        for promo in LAUNCH_PROMOTIONS:
            product = products_by_key[promo["product_key"]]
            store = stores_by_slug[promo["store_slug"]]
            _, created = Promotion.objects.update_or_create(
                store=store,
                product=product,
                title=promo["title"],
                defaults={
                    "description": promo["description"],
                    "category": promo["category"],
                    "is_active": True,
                },
            )
            self.stdout.write(
                f"  Promotion {promo['title']} {'created' if created else 'updated'}"
            )

        ensure_house_ads_seeded()
        self.stdout.write("  House ad placements seeded")

        try:
            from apps.price_intelligence.search import reindex_products

            n = reindex_products(products_by_key.values())
            if n:
                self.stdout.write(f"  Typesense reindexed {n} products")
        except Exception:  # noqa: BLE001
            pass

        self._ensure_scrape_beat_task()

        self.stdout.write(self.style.SUCCESS("Launch seed data complete."))

    def _ensure_scrape_beat_task(self):
        """Register hourly catalogue scrape for django_celery_beat (M8)."""
        try:
            from django_celery_beat.models import IntervalSchedule, PeriodicTask
        except Exception:  # noqa: BLE001
            return

        schedule, _ = IntervalSchedule.objects.get_or_create(
            every=1,
            period=IntervalSchedule.HOURS,
        )
        PeriodicTask.objects.update_or_create(
            name="scrape-catalogue-prices-hourly",
            defaults={
                "interval": schedule,
                "task": "price_intelligence.scrape_catalogue_prices",
                "args": '["ZA"]',
                "enabled": True,
            },
        )
        self.stdout.write("  Celery beat: scrape-catalogue-prices-hourly")
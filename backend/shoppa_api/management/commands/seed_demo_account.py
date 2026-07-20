"""Seed catalogue-linked shopping lists for the local demo account.

Idempotent: safe to re-run. Ensures launch catalogue/prices exist, then
creates starter lists for demo@shoppa.app with product_id links so price
comparison, promotions, and product search work out of the box.
"""
from django.core.management import call_command
from django.core.management.base import BaseCommand

from apps.lists.models import ListCategory, ListItem, ShoppingList
from apps.price_intelligence.models import Product
from apps.users.models import User

DEMO_EMAIL = "demo@shoppa.app"

# List title -> product display names (must match seed_launch_data catalogue).
DEMO_LISTS = {
    "Weekly Groceries": {
        "category": ListCategory.GROCERIES,
        "products": [
            ("Full Cream Milk 2L", 2),
            ("Brown Bread 700g", 1),
            ("Large Eggs ×18", 1),
            ("Chicken Breasts 1kg", 1),
            ("Basmati Rice 2kg", 1),
        ],
    },
    "Pantry Staples": {
        "category": ListCategory.GROCERIES,
        "products": [
            ("Ground Coffee 250g", 1),
            ("Bananas 1kg", 2),
            ("Cheddar Cheese 800g", 1),
        ],
    },
}


class Command(BaseCommand):
    help = "Seed demo shopping lists with catalogue products for demo@shoppa.app."

    def add_arguments(self, parser):
        parser.add_argument(
            "--email",
            default=DEMO_EMAIL,
            help=f"Demo user email (default: {DEMO_EMAIL})",
        )

    def handle(self, *args, **options):
        email = options["email"]
        user = User.objects.filter(email__iexact=email).first()
        if user is None:
            self.stderr.write(
                self.style.ERROR(f"User {email} not found — register the account first.")
            )
            return

        call_command("seed_launch_data", verbosity=0)
        self.stdout.write("Launch catalogue and prices ensured.")

        products_by_name = {
            p.name: p
            for p in Product.objects.filter(region=user.region or "ZA")
        }

        for title, spec in DEMO_LISTS.items():
            shopping_list, created = ShoppingList.objects.get_or_create(
                owner=user,
                title=title,
                defaults={"category": spec["category"]},
            )
            if not created and shopping_list.category != spec["category"]:
                shopping_list.category = spec["category"]
                shopping_list.save(update_fields=["category"])

            ListItem.objects.filter(list=shopping_list).delete()
            for position, (product_name, quantity) in enumerate(spec["products"]):
                product = products_by_name.get(product_name)
                if product is None:
                    self.stderr.write(
                        self.style.WARNING(f"  Skipping missing product: {product_name}")
                    )
                    continue
                ListItem.objects.create(
                    list=shopping_list,
                    name=product.name,
                    product_id=product.id,
                    quantity=quantity,
                    position=position,
                )

            item_count = shopping_list.items.count()
            self.stdout.write(
                f"  List '{title}' — {item_count} items "
                f"({'created' if created else 'refreshed'})"
            )

        self.stdout.write(
            self.style.SUCCESS(f"Demo lists seeded for {email}.")
        )
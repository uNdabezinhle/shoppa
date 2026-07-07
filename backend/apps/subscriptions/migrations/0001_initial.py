import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


def seed_plans(apps, schema_editor):
    SubscriptionPlan = apps.get_model("subscriptions", "SubscriptionPlan")
    plans = [
        ("free", "Free", 0, [], 3, 0),
        ("personal_premium", "Personal Premium", 4900, ["unlimited_lists", "ads_free"], None, 1),
        (
            "professional",
            "Professional",
            9900,
            [
                "unlimited_lists",
                "scale_lists",
                "publish_lists",
                "event_lists",
                "ads_free",
            ],
            None,
            2,
        ),
    ]
    for slug, name, price, features, max_lists, order in plans:
        SubscriptionPlan.objects.update_or_create(
            slug=slug,
            defaults={
                "name": name,
                "price_monthly": price,
                "currency_code": "ZAR",
                "features": features,
                "max_owned_lists": max_lists,
                "is_active": True,
                "sort_order": order,
            },
        )


class Migration(migrations.Migration):
    initial = True

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name="SubscriptionPlan",
            fields=[
                (
                    "slug",
                    models.SlugField(max_length=40, primary_key=True, serialize=False),
                ),
                ("name", models.CharField(max_length=100)),
                ("price_monthly", models.PositiveIntegerField()),
                ("currency_code", models.CharField(default="ZAR", max_length=3)),
                ("features", models.JSONField(blank=True, default=list)),
                (
                    "max_owned_lists",
                    models.PositiveIntegerField(blank=True, null=True),
                ),
                ("is_active", models.BooleanField(default=True)),
                ("sort_order", models.PositiveSmallIntegerField(default=0)),
            ],
            options={
                "ordering": ["sort_order", "slug"],
            },
        ),
        migrations.CreateModel(
            name="UserSubscription",
            fields=[
                (
                    "id",
                    models.BigAutoField(
                        auto_created=True,
                        primary_key=True,
                        serialize=False,
                        verbose_name="ID",
                    ),
                ),
                (
                    "status",
                    models.CharField(
                        choices=[
                            ("active", "Active"),
                            ("canceled", "Canceled"),
                            ("past_due", "Past due"),
                        ],
                        default="active",
                        max_length=20,
                    ),
                ),
                (
                    "stripe_customer_id",
                    models.CharField(blank=True, default="", max_length=120),
                ),
                (
                    "stripe_subscription_id",
                    models.CharField(blank=True, default="", max_length=120),
                ),
                ("current_period_end", models.DateTimeField(blank=True, null=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "plan",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="subscribers",
                        to="subscriptions.subscriptionplan",
                    ),
                ),
                (
                    "user",
                    models.OneToOneField(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="subscription",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "ordering": ["-created_at"],
            },
        ),
        migrations.RunPython(seed_plans, migrations.RunPython.noop),
    ]
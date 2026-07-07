import uuid

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):
    initial = True

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name="AdPlacement",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid4,
                        editable=False,
                        primary_key=True,
                        serialize=False,
                    ),
                ),
                ("slug", models.SlugField(max_length=80, unique=True)),
                ("title", models.CharField(max_length=120)),
                ("body", models.TextField(blank=True, default="")),
                ("cta_text", models.CharField(blank=True, default="", max_length=60)),
                ("cta_url", models.URLField(blank=True, default="")),
                (
                    "surface",
                    models.CharField(
                        choices=[
                            ("home", "Home"),
                            ("list", "List"),
                            ("checkout", "Checkout"),
                        ],
                        max_length=20,
                    ),
                ),
                (
                    "ad_format",
                    models.CharField(
                        choices=[
                            ("banner", "Banner"),
                            ("native", "Native"),
                            ("interstitial", "Interstitial"),
                            ("rewarded", "Rewarded"),
                        ],
                        max_length=20,
                    ),
                ),
                (
                    "sponsor_name",
                    models.CharField(blank=True, default="", max_length=80),
                ),
                ("is_active", models.BooleanField(default=True)),
                ("sort_order", models.PositiveSmallIntegerField(default=0)),
            ],
            options={
                "ordering": ["sort_order", "slug"],
            },
        ),
        migrations.CreateModel(
            name="AdImpression",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid4,
                        editable=False,
                        primary_key=True,
                        serialize=False,
                    ),
                ),
                (
                    "surface",
                    models.CharField(
                        choices=[
                            ("home", "Home"),
                            ("list", "List"),
                            ("checkout", "Checkout"),
                        ],
                        max_length=20,
                    ),
                ),
                (
                    "ad_format",
                    models.CharField(
                        choices=[
                            ("banner", "Banner"),
                            ("native", "Native"),
                            ("interstitial", "Interstitial"),
                            ("rewarded", "Rewarded"),
                        ],
                        max_length=20,
                    ),
                ),
                (
                    "session_key",
                    models.CharField(
                        blank=True, db_index=True, default="", max_length=120
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                (
                    "placement",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="impressions",
                        to="ads.adplacement",
                    ),
                ),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="ad_impressions",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "ordering": ["-created_at"],
            },
        ),
        migrations.CreateModel(
            name="AdClick",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid4,
                        editable=False,
                        primary_key=True,
                        serialize=False,
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                (
                    "placement",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="clicks",
                        to="ads.adplacement",
                    ),
                ),
                (
                    "user",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="ad_clicks",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={
                "ordering": ["-created_at"],
            },
        ),
    ]
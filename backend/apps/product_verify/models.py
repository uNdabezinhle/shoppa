"""Food product verification models (GTIN snapshots, allergen profile, corrections)."""
import uuid

from django.conf import settings
from django.db import models


class GtinSource(models.TextChoices):
    OFF = "off", "Open Food Facts"
    MANUAL = "manual", "Manual"
    MERGED = "merged", "Merged"


class GtinProduct(models.Model):
    """Cached food product identity + safety metadata keyed by GTIN."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    gtin = models.CharField(max_length=14, unique=True, db_index=True)
    name = models.CharField(max_length=300, blank=True, default="")
    brand = models.CharField(max_length=200, blank=True, default="")
    image_url = models.URLField(max_length=500, blank=True, default="")
    ingredients_text = models.TextField(blank=True, default="")
    allergens = models.JSONField(default=list, blank=True)
    traces = models.JSONField(default=list, blank=True)
    nutriments = models.JSONField(default=dict, blank=True)
    categories = models.JSONField(default=list, blank=True)
    nutriscore_grade = models.CharField(max_length=8, blank=True, default="")
    quantity = models.CharField(max_length=80, blank=True, default="")
    source = models.CharField(
        max_length=16, choices=GtinSource.choices, default=GtinSource.OFF
    )
    region = models.CharField(max_length=8, default="ZA")
    found = models.BooleanField(default=True)
    raw_hash = models.CharField(max_length=64, blank=True, default="")
    shoppa_product = models.ForeignKey(
        "price_intelligence.Product",
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="gtin_products",
    )
    fetched_at = models.DateTimeField(auto_now=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-fetched_at"]

    def __str__(self):
        return f"{self.gtin} {self.name}".strip()


class UserAllergenProfile(models.Model):
    """POPIA-sensitive dietary allergen preferences for one user."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="allergen_profile",
    )
    allergens = models.JSONField(default=list, blank=True)
    consent_at = models.DateTimeField(null=True, blank=True)
    updated_at = models.DateTimeField(auto_now=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return f"AllergenProfile({self.user_id})"


class ProductCorrection(models.Model):
    """Community correction / missing-product report."""

    class Status(models.TextChoices):
        PENDING = "pending", "Pending"
        REVIEWED = "reviewed", "Reviewed"
        DISMISSED = "dismissed", "Dismissed"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="product_corrections",
    )
    gtin = models.CharField(max_length=14, db_index=True)
    field = models.CharField(max_length=64)
    suggested_value = models.TextField(blank=True, default="")
    note = models.TextField(blank=True, default="")
    status = models.CharField(
        max_length=16, choices=Status.choices, default=Status.PENDING
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]


class ScanEvent(models.Model):
    """Optional server-side scan history for multi-device sync."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="scan_events",
    )
    gtin = models.CharField(max_length=14, db_index=True)
    level = models.CharField(max_length=16, blank=True, default="")
    product_name = models.CharField(max_length=300, blank=True, default="")
    scanned_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-scanned_at"]
        indexes = [
            models.Index(fields=["user", "-scanned_at"]),
        ]

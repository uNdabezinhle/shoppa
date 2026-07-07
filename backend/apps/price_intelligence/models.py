"""Price Intelligence (Solution Architecture §4/§6: `price_intelligence`
app). Covers SRS FR-5.1 (ingest from crowd-sourcing, scraping, and store
data), FR-5.2 (reconcile conflicting prices by recency and trust score),
laying the groundwork for FR-5.3 (list comparison, views.py) and FR-5.4
(price-drop alerts, services.py).

Region-scoped per Architecture §5.1 (region column on stores/products,
mirroring users); money is integer minor units, matching the API
Specification's money convention.
"""
import uuid

from django.conf import settings
from django.db import models


class Store(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=200)
    region = models.CharField(max_length=8, default="ZA")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["name"]

    def __str__(self):
        return self.name


class Product(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=200)
    region = models.CharField(max_length=8, default="ZA")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["name"]

    def __str__(self):
        return self.name


class PriceSource(models.TextChoices):
    CROWD = "crowd", "Crowd-sourced"
    SCRAPED = "scraped", "Scraped"
    STORE = "store", "Store feed"


class PriceObservation(models.Model):
    """A single recorded price for a product at a store, from any source
    (API Specification Definitions §1.3). Ingestion (FR-5.1) always lands
    here first; reconciliation (FR-5.2, see services.reconcile) then
    decides whether it moves the authoritative CurrentPrice.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    product = models.ForeignKey(
        Product, on_delete=models.CASCADE, related_name="observations"
    )
    store = models.ForeignKey(
        Store, on_delete=models.CASCADE, related_name="observations"
    )
    price = models.PositiveIntegerField()  # minor units
    source = models.CharField(max_length=10, choices=PriceSource.choices)
    # Null for scraped/store-feed observations, which have no contributing
    # user; set for crowd-sourced ones, whose weight depends on this
    # user's trust_score (FR-5.2).
    submitted_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="price_observations",
    )
    observed_at = models.DateTimeField()
    # FR-5.2 / QA Test Plan TC-5.3: an outlier beyond the configured band
    # is quarantined -- kept for review/audit, but excluded from
    # reconciliation so it never reaches CurrentPrice or a client.
    is_quarantined = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-observed_at"]

    def __str__(self):
        return f"{self.product} @ {self.store}: {self.price}"


class Confidence(models.TextChoices):
    HIGH = "high", "High"
    MEDIUM = "medium", "Medium"
    LOW = "low", "Low"


class CurrentPrice(models.Model):
    """The reconciled, authoritative price for a (product, store) pair
    (Architecture §6.1: "each product/store pair resolves to a current
    price plus a confidence indicator"). Recomputed by
    services.reconcile() whenever a new non-quarantined observation
    lands.
    """

    product = models.ForeignKey(
        Product, on_delete=models.CASCADE, related_name="current_prices"
    )
    store = models.ForeignKey(
        Store, on_delete=models.CASCADE, related_name="current_prices"
    )
    price = models.PositiveIntegerField()
    confidence = models.CharField(max_length=10, choices=Confidence.choices)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["product", "store"], name="unique_current_price"
            )
        ]

    def __str__(self):
        return f"{self.product} @ {self.store}: {self.price} ({self.confidence})"


class PriceAlert(models.Model):
    """A detected price drop on a product a user has on one of their
    lists (SRS FR-5.4). Created synchronously by services.reconcile()
    when a drop crosses the threshold -- this is the data record only;
    actual push delivery (Celery Beat + FCM, per Architecture §3) is a
    later follow-up once the notifications app exists.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="price_alerts"
    )
    product = models.ForeignKey(Product, on_delete=models.CASCADE)
    store = models.ForeignKey(Store, on_delete=models.CASCADE)
    old_price = models.PositiveIntegerField()
    new_price = models.PositiveIntegerField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.user}: {self.product} dropped {self.old_price} -> {self.new_price}"

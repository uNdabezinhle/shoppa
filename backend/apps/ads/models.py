"""House-sold ad placements and impression tracking (SRS FR-10.1–FR-10.6)."""
import uuid

from django.conf import settings
from django.db import models


class AdSurface(models.TextChoices):
    HOME = "home", "Home"
    LIST = "list", "List"
    CHECKOUT = "checkout", "Checkout"


class AdFormat(models.TextChoices):
    BANNER = "banner", "Banner"
    NATIVE = "native", "Native"
    INTERSTITIAL = "interstitial", "Interstitial"
    REWARDED = "rewarded", "Rewarded"


class AdPlacement(models.Model):
    """House-sold creative served to free-tier users."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    slug = models.SlugField(max_length=80, unique=True)
    title = models.CharField(max_length=120)
    body = models.TextField(blank=True, default="")
    cta_text = models.CharField(max_length=60, blank=True, default="")
    cta_url = models.URLField(blank=True, default="")
    surface = models.CharField(max_length=20, choices=AdSurface.choices)
    ad_format = models.CharField(max_length=20, choices=AdFormat.choices)
    sponsor_name = models.CharField(max_length=80, blank=True, default="")
    is_active = models.BooleanField(default=True)
    sort_order = models.PositiveSmallIntegerField(default=0)

    class Meta:
        ordering = ["sort_order", "slug"]

    def __str__(self):
        return f"{self.slug} ({self.ad_format}@{self.surface})"


class AdImpression(models.Model):
    """Recorded when a placement is shown — used for reporting and capping."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="ad_impressions",
    )
    placement = models.ForeignKey(
        AdPlacement,
        on_delete=models.CASCADE,
        related_name="impressions",
    )
    surface = models.CharField(max_length=20, choices=AdSurface.choices)
    ad_format = models.CharField(max_length=20, choices=AdFormat.choices)
    session_key = models.CharField(max_length=120, blank=True, default="", db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]


class AdClick(models.Model):
    """Click-through on a house ad."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="ad_clicks",
    )
    placement = models.ForeignKey(
        AdPlacement,
        on_delete=models.CASCADE,
        related_name="clicks",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
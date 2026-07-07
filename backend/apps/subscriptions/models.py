"""Subscription plans and per-user entitlements (SRS FR-9.1–FR-9.3)."""
from django.conf import settings
from django.db import models


class SubscriptionPlan(models.Model):
    slug = models.SlugField(primary_key=True, max_length=40)
    name = models.CharField(max_length=100)
    price_monthly = models.PositiveIntegerField(
        help_text="Minor units, e.g. 4900 = R49.00"
    )
    currency_code = models.CharField(max_length=3, default="ZAR")
    features = models.JSONField(
        default=list,
        blank=True,
        help_text="Feature-flag strings, e.g. scale_lists, ads_free",
    )
    max_owned_lists = models.PositiveIntegerField(
        null=True,
        blank=True,
        help_text="Null means unlimited owned lists",
    )
    is_active = models.BooleanField(default=True)
    sort_order = models.PositiveSmallIntegerField(default=0)

    class Meta:
        ordering = ["sort_order", "slug"]

    def __str__(self):
        return self.name


class UserSubscription(models.Model):
    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        CANCELED = "canceled", "Canceled"
        PAST_DUE = "past_due", "Past due"

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="subscription",
    )
    plan = models.ForeignKey(
        SubscriptionPlan,
        on_delete=models.PROTECT,
        related_name="subscribers",
    )
    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.ACTIVE,
    )
    stripe_customer_id = models.CharField(max_length=120, blank=True, default="")
    stripe_subscription_id = models.CharField(max_length=120, blank=True, default="")
    current_period_end = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.user} → {self.plan_id} ({self.status})"
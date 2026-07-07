"""Promotions (Solution Architecture §4/§6: `promotions` app -- targeting
engine, campaigns, coupons). Covers SRS FR-7.1 (target users whose lists
contain matching products), FR-7.2 (non-intrusive item flagging, see
apps.lists.serializers.ListItemSerializer.has_promotion), and FR-7.3
(per-store or per-category opt-out).
"""
import uuid

from django.conf import settings
from django.db import models
from django.db.models import Q

from apps.lists.models import ListCategory
from apps.price_intelligence.models import Product, Store


class Promotion(models.Model):
    """A store's campaign on a specific product (API Specification §6.6:
    GET /promotions "matched to the user's active list contents").
    category mirrors apps.lists.models.ListCategory so a user's
    category-level opt-out (FR-7.3) lines up with the same vocabulary
    they see when creating lists.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    store = models.ForeignKey(
        Store, on_delete=models.CASCADE, related_name="promotions"
    )
    product = models.ForeignKey(
        Product, on_delete=models.CASCADE, related_name="promotions"
    )
    category = models.CharField(
        max_length=20, choices=ListCategory.choices, default=ListCategory.CUSTOM
    )
    title = models.CharField(max_length=200)
    description = models.CharField(max_length=280, blank=True, default="")
    is_active = models.BooleanField(default=True)
    # Optional campaign window -- a promotion with either left null runs
    # indefinitely on that side (FR-7.1 doesn't require a schedule; this
    # just lets one be set when a store wants it).
    starts_at = models.DateTimeField(null=True, blank=True)
    ends_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.title} ({self.store})"


class PromotionOptOut(models.Model):
    """FR-7.3: a user opting out of promotions from one store, or from an
    entire category, across all stores. Exactly one of store/category is
    set -- enforced by the CheckConstraint below and mirrored in
    PromotionOptOutSerializer.validate() for a clean 422 instead of a raw
    IntegrityError.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="promotion_opt_outs",
    )
    store = models.ForeignKey(
        Store,
        null=True,
        blank=True,
        on_delete=models.CASCADE,
        related_name="opt_outs",
    )
    category = models.CharField(
        max_length=20, choices=ListCategory.choices, blank=True, default=""
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [
            models.CheckConstraint(
                check=(
                    (Q(store__isnull=False) & Q(category=""))
                    | (Q(store__isnull=True) & ~Q(category=""))
                ),
                name="promotion_optout_exactly_one_target",
            ),
            models.UniqueConstraint(
                fields=["user", "store"],
                condition=Q(store__isnull=False),
                name="unique_user_store_optout",
            ),
            models.UniqueConstraint(
                fields=["user", "category"],
                condition=~Q(category=""),
                name="unique_user_category_optout",
            ),
        ]

    def __str__(self):
        target = self.store or self.category
        return f"{self.user}: opted out of {target}"

"""Targeting engine (SRS FR-7.1, FR-7.3). A promotion matches a user if
its product is on one of the user's accessible lists (owned or shared)
and the user hasn't opted out of its store or its category.
"""
from django.db.models import Q
from django.utils import timezone

from .models import Promotion, PromotionOptOut


def _accessible_list_ids(user):
    # Mirrors apps.lists.views._accessible_lists's owner-or-collaborator
    # rule, inlined here rather than imported: apps.lists already depends
    # on apps.promotions (for the item-flagging serializer field, FR-7.2),
    # so importing back from apps.lists at module load time would be
    # circular. A plain Q-filter is cheap to keep in sync since the rule
    # itself is simple and unlikely to change independently in one place
    # only.
    from apps.lists.models import ShoppingList

    return ShoppingList.objects.filter(
        Q(owner=user) | Q(collaborators__user=user)
    ).values_list("id", flat=True)


def _targeted_product_ids(user):
    from apps.lists.models import ListItem

    return (
        ListItem.objects.filter(list_id__in=_accessible_list_ids(user))
        .exclude(product_id__isnull=True)
        .values_list("product_id", flat=True)
        .distinct()
    )


def _user_has_product_on_a_list(user, product_id):
    from apps.lists.models import ListItem

    return ListItem.objects.filter(
        list_id__in=_accessible_list_ids(user), product_id=product_id
    ).exists()


def _opted_out_store_ids(user):
    return set(
        PromotionOptOut.objects.filter(user=user, store__isnull=False).values_list(
            "store_id", flat=True
        )
    )


def _opted_out_categories(user):
    return set(
        PromotionOptOut.objects.filter(user=user)
        .exclude(category="")
        .values_list("category", flat=True)
    )


def _live_promotions():
    now = timezone.now()
    return Promotion.objects.filter(is_active=True).filter(
        Q(starts_at__isnull=True) | Q(starts_at__lte=now)
    ).filter(Q(ends_at__isnull=True) | Q(ends_at__gte=now))


def active_promotions_for_user(user):
    """FR-7.1/FR-7.3: promotions on products the user has on an
    accessible list, minus anything they've opted out of. Used both by
    GET /promotions and (via has_active_promotion) the per-item flag on
    list views (FR-7.2).
    """
    product_ids = list(_targeted_product_ids(user))
    if not product_ids:
        return Promotion.objects.none()

    qs = _live_promotions().filter(product_id__in=product_ids)

    opted_out_stores = _opted_out_store_ids(user)
    if opted_out_stores:
        qs = qs.exclude(store_id__in=opted_out_stores)

    opted_out_categories = _opted_out_categories(user)
    if opted_out_categories:
        qs = qs.exclude(category__in=opted_out_categories)

    return qs.select_related("store", "product")


def has_active_promotion(user, product_id):
    """FR-7.2: does this specific product have a live, non-opted-out
    promotion targeting this user? Re-checks that the product is
    actually on one of the user's accessible lists (FR-7.1) rather than
    trusting the caller -- cheap single-query check, and keeps this
    function correct on its own regardless of what it's called with.
    """
    if product_id is None:
        return False
    if not _user_has_product_on_a_list(user, product_id):
        return False

    qs = _live_promotions().filter(product_id=product_id)
    opted_out_stores = _opted_out_store_ids(user)
    if opted_out_stores:
        qs = qs.exclude(store_id__in=opted_out_stores)
    opted_out_categories = _opted_out_categories(user)
    if opted_out_categories:
        qs = qs.exclude(category__in=opted_out_categories)
    return qs.exists()

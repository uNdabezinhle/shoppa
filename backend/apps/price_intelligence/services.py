"""Reconciliation and observation-recording logic (SRS FR-5.1, FR-5.2,
FR-5.4; Architecture §6.1). Kept out of views.py so both the REST
endpoint and the implicit observation on item check-off (apps.lists)
share exactly one code path.
"""
import statistics

from django.utils import timezone

from .models import Confidence, CurrentPrice, PriceAlert, PriceObservation, PriceSource

#: A new observation more than this ratio away from the recent median is
#: quarantined rather than reconciled (Architecture §6.1: "outliers beyond
#: a configurable band are quarantined for review").
OUTLIER_LOW_RATIO = 0.5
OUTLIER_HIGH_RATIO = 2.0

#: Source baseline weights before trust/recency are applied (Architecture
#: §6.1: "crowd-sourced prices are weighted by contributor trust score and
#: recency" / "scraped prices establish a baseline where user data is
#: sparse" -- store feeds are the most authoritative, hence the highest
#: baseline).
_SOURCE_BASELINE_WEIGHT = {
    PriceSource.STORE: 1.0,
    PriceSource.SCRAPED: 0.8,
    PriceSource.CROWD: 0.6,
}

#: A reconciled price is only "high" confidence once it's backed by
#: enough accumulated weight -- a single crowd submission from a
#: middling-trust user shouldn't look as authoritative as a store feed.
_HIGH_CONFIDENCE_WEIGHT = 1.5
_MEDIUM_CONFIDENCE_WEIGHT = 0.6

#: A drop smaller than this is noise, not an alert-worthy trend (FR-5.4).
PRICE_DROP_ALERT_THRESHOLD = 0.05


def _is_outlier(new_price, recent_prices):
    if not recent_prices:
        return False
    median = statistics.median(recent_prices)
    if median <= 0:
        return False
    ratio = new_price / median
    return ratio < OUTLIER_LOW_RATIO or ratio > OUTLIER_HIGH_RATIO


def record_observation(
    *, product, store, price, source, observed_at=None, submitted_by=None
):
    """Ingests one price observation (FR-5.1), quarantining it instead of
    reconciling if it's an outlier against recent non-quarantined
    observations for the same product/store (FR-5.2, TC-5.3). Returns the
    created PriceObservation.
    """
    observed_at = observed_at or timezone.now()
    recent_prices = list(
        PriceObservation.objects.filter(
            product=product, store=store, is_quarantined=False
        )
        .order_by("-observed_at")
        .values_list("price", flat=True)[:20]
    )
    is_outlier = _is_outlier(price, recent_prices)

    observation = PriceObservation.objects.create(
        product=product,
        store=store,
        price=price,
        source=source,
        submitted_by=submitted_by,
        observed_at=observed_at,
        is_quarantined=is_outlier,
    )

    if not is_outlier:
        reconcile(product, store)

    return observation


def reconcile(product, store):
    """Recomputes CurrentPrice for (product, store) from recent,
    non-quarantined observations: each observation is weighted by its
    source baseline, the submitting user's trust_score (crowd-sourced
    only), and an exponential recency decay, then combined into a
    weighted average (FR-5.2). Fires a PriceAlert if this moves the price
    down beyond the drop threshold (FR-5.4). Returns the resulting
    CurrentPrice, or None if there's nothing to reconcile from.
    """
    observations = list(
        PriceObservation.objects.filter(
            product=product, store=store, is_quarantined=False
        ).order_by("-observed_at")[:20]
    )
    if not observations:
        return None

    now = timezone.now()
    weighted_sum = 0.0
    weight_total = 0.0
    for obs in observations:
        age_hours = max((now - obs.observed_at).total_seconds() / 3600, 0)
        recency_weight = 1.0 / (1.0 + age_hours / 24)  # halves roughly every day
        source_weight = _SOURCE_BASELINE_WEIGHT[obs.source]
        if obs.source == PriceSource.CROWD:
            trust = obs.submitted_by.trust_score if obs.submitted_by else 0.5
            source_weight *= trust
        weight = source_weight * recency_weight
        weighted_sum += weight * obs.price
        weight_total += weight

    if weight_total <= 0:
        return None

    reconciled_price = round(weighted_sum / weight_total)
    if weight_total >= _HIGH_CONFIDENCE_WEIGHT:
        confidence = Confidence.HIGH
    elif weight_total >= _MEDIUM_CONFIDENCE_WEIGHT:
        confidence = Confidence.MEDIUM
    else:
        confidence = Confidence.LOW

    previous = CurrentPrice.objects.filter(product=product, store=store).first()
    old_price = previous.price if previous else None

    current, _ = CurrentPrice.objects.update_or_create(
        product=product,
        store=store,
        defaults={"price": reconciled_price, "confidence": confidence},
    )

    if old_price is not None and reconciled_price < old_price:
        drop_ratio = (old_price - reconciled_price) / old_price
        if drop_ratio >= PRICE_DROP_ALERT_THRESHOLD:
            _create_price_drop_alerts(product, store, old_price, reconciled_price)

    return current


#: Region -> currency code, matching the API Specification's money
#: convention (integer minor units + currency_code). Only ZA is modeled
#: today (Architecture §5.1 launches in ZA); default to ZAR for any
#: region not yet mapped rather than raising, since this only affects
#: display, not money math.
_REGION_CURRENCY = {"ZA": "ZAR"}


def compare_stores_for_list(shopping_list):
    """FR-5.3: for every store that has a CurrentPrice for *every* priced
    item on the list, compute the total cost of doing the whole list at
    that store, then rank stores cheapest-first. Items with no
    product_id (free-text entries not linked to the catalogue) can't be
    matched to a price and are excluded from the comparison entirely --
    if that leaves zero priced items, there's nothing to compare.
    Returns a dict shaped like the API Specification's
    GET /lists/{id}/comparison response.
    """
    currency_code = _REGION_CURRENCY.get(shopping_list.owner.region, "ZAR")

    priced_items = list(
        shopping_list.items.exclude(product_id__isnull=True).values_list(
            "product_id", "quantity"
        )
    )
    if not priced_items:
        return {"currency_code": currency_code, "stores": [], "best": None}

    product_ids = [product_id for product_id, _ in priced_items]
    current_prices = CurrentPrice.objects.filter(
        product_id__in=product_ids
    ).select_related("store")

    by_store = {}
    for cp in current_prices:
        by_store.setdefault(cp.store_id, {})[cp.product_id] = cp

    confidence_rank = {Confidence.LOW: 0, Confidence.MEDIUM: 1, Confidence.HIGH: 2}
    stores = []
    for store_id, priced_by_product in by_store.items():
        # A store only qualifies if it has a reconciled price for every
        # item being compared -- a partial basket isn't a fair total.
        if not all(pid in priced_by_product for pid in product_ids):
            continue

        total = 0
        weakest_confidence = Confidence.HIGH
        for product_id, quantity in priced_items:
            current_price = priced_by_product[product_id]
            total += round(current_price.price * float(quantity))
            if confidence_rank[current_price.confidence] < confidence_rank[weakest_confidence]:
                weakest_confidence = current_price.confidence

        store = next(iter(priced_by_product.values())).store
        stores.append(
            {
                "store_id": store.id,
                "name": store.name,
                "total": total,
                "confidence": weakest_confidence,
            }
        )

    stores.sort(key=lambda entry: entry["total"])

    best = None
    if stores:
        saves = stores[1]["total"] - stores[0]["total"] if len(stores) > 1 else 0
        best = {"store_id": stores[0]["store_id"], "saves": saves}

    return {"currency_code": currency_code, "stores": stores, "best": best}


def _create_price_drop_alerts(product, store, old_price, new_price):
    # Lazy import: apps.lists depends on apps.price_intelligence (for the
    # implicit observation on check-off), so importing it back here at
    # module load time would be circular. Importing inside the function
    # body avoids that while still letting price_intelligence know which
    # users have this product on a list.
    from apps.lists.models import ShoppingList

    owner_ids = (
        ShoppingList.objects.filter(items__product_id=product.id)
        .values_list("owner_id", flat=True)
        .distinct()
    )
    user_ids = list(owner_ids)
    PriceAlert.objects.bulk_create(
        [
            PriceAlert(
                user_id=owner_id,
                product=product,
                store=store,
                old_price=old_price,
                new_price=new_price,
            )
            for owner_id in user_ids
        ]
    )
    from apps.notifications.services import create_price_drop_notifications

    create_price_drop_notifications(
        product, store, old_price, new_price, user_ids
    )

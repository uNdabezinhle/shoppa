"""Launch adapters backed by crowd-sourced / seed catalogue prices (AD-2).

Each platform maps to a physical retailer's reconciled prices until
official delivery APIs are available.
"""
from typing import Sequence
from uuid import UUID

from apps.price_intelligence.models import CurrentPrice

from .base import DeliveryAdapter, DeliveryItem, DeliveryQuoteResult

# Platform -> underlying store name in the price_intelligence catalogue.
_PLATFORM_STORE = {
    "checkers_6060": "Checkers",
    "pnp_asap": "Pick n Pay",
    "spar_2u": "SPAR",
    "woolies_dash": "Woolworths",
}

# Fees and ETAs from the interactive prototype (docs/shoppa-prototype.jsx).
_PLATFORM_META = {
    "checkers_6060": {"fee": 2500, "eta": 60, "display": "Checkers 60/60"},
    "pnp_asap": {"fee": 3500, "eta": 75, "display": "Pick n Pay ASAP"},
    "spar_2u": {"fee": 2900, "eta": 90, "display": "SPAR 2U"},
    "woolies_dash": {"fee": 0, "eta": 120, "display": "Woolies Dash"},
}

# Spar 2U seed behaviour: one catalogue item may be unavailable.
_UNAVAILABLE_ON_SPAR = 1


def _affiliate_url(platform: str, list_id: UUID) -> str:
    return f"https://{platform}.shoppa.app/order?aff=shoppa&list_id={list_id}"


class SeededDeliveryAdapter(DeliveryAdapter):
    def __init__(self, platform_id: str):
        meta = _PLATFORM_META[platform_id]
        self.platform_id = platform_id
        self.display_name = meta["display"]
        self._store_name = _PLATFORM_STORE[platform_id]
        self._delivery_fee = meta["fee"]
        self._eta_minutes = meta["eta"]

    def quote(
        self,
        items: Sequence[DeliveryItem],
        *,
        region: str,
        list_id: UUID,
    ) -> DeliveryQuoteResult:
        total_items = len(items)
        if total_items == 0:
            return DeliveryQuoteResult(
                platform=self.platform_id,
                display_name=self.display_name,
                subtotal=0,
                delivery_fee=self._delivery_fee,
                total=self._delivery_fee,
                eta_minutes=self._eta_minutes,
                available_items=0,
                total_items=0,
                order_url=_affiliate_url(self.platform_id, list_id),
            )

        product_ids = [item.product_id for item in items]
        prices = CurrentPrice.objects.filter(
            product_id__in=product_ids,
            store__name=self._store_name,
            store__region=region,
        ).select_related("store")
        by_product = {price.product_id: price for price in prices}

        available_items = 0
        subtotal = 0
        for item in items:
            current = by_product.get(item.product_id)
            if current is None:
                continue
            available_items += 1
            subtotal += round(current.price * float(item.quantity))

        if self.platform_id == "spar_2u" and available_items > 0:
            available_items = max(0, available_items - _UNAVAILABLE_ON_SPAR)

        total = subtotal + self._delivery_fee
        return DeliveryQuoteResult(
            platform=self.platform_id,
            display_name=self.display_name,
            subtotal=subtotal,
            delivery_fee=self._delivery_fee,
            total=total,
            eta_minutes=self._eta_minutes,
            available_items=available_items,
            total_items=total_items,
            order_url=_affiliate_url(self.platform_id, list_id),
        )


def build_seeded_adapter(platform_id: str) -> SeededDeliveryAdapter:
    return SeededDeliveryAdapter(platform_id)
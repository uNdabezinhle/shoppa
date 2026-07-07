"""Delivery quote orchestration (FR-6.1, FR-6.2)."""
import logging

from apps.price_intelligence.services import _REGION_CURRENCY

from .adapters.base import DeliveryItem
from .adapters.registry import get_adapters_for_region

logger = logging.getLogger(__name__)


def _serialize_quote(quote):
    return {
        "platform": quote.platform,
        "display_name": quote.display_name,
        "subtotal": quote.subtotal,
        "delivery_fee": quote.delivery_fee,
        "total": quote.total,
        "eta_minutes": quote.eta_minutes,
        "available_items": quote.available_items,
        "total_items": quote.total_items,
        "order_url": quote.order_url,
    }


def get_delivery_quotes_for_list(shopping_list):
    """Build ranked delivery quotes for catalogue-linked list items."""
    region = shopping_list.owner.region
    currency_code = _REGION_CURRENCY.get(region, "ZAR")

    items = [
        DeliveryItem(
            product_id=item.product_id,
            quantity=float(item.quantity),
            name=item.name,
        )
        for item in shopping_list.items.exclude(product_id__isnull=True)
    ]

    quotes = []
    for adapter in get_adapters_for_region(region):
        try:
            result = adapter.quote(items, region=region, list_id=shopping_list.id)
            quotes.append(result)
        except Exception:
            logger.exception(
                "Delivery adapter %s failed for list %s",
                adapter.platform_id,
                shopping_list.id,
            )

    quotes.sort(key=lambda entry: entry.total)
    return {
        "currency_code": currency_code,
        "quotes": [_serialize_quote(quote) for quote in quotes],
    }
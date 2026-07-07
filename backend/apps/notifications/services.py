"""Bridge price intelligence events into the in-app feed (TC-5.5)."""


def create_price_drop_notifications(product, store, old_price, new_price, user_ids):
    """Creates one in-app notification per affected list owner."""
    from .models import Notification, NotificationKind

    if not user_ids:
        return []

    drop = old_price - new_price
    title = f"Price drop on {product.name}"
    body = (
        f"{store.name}: now R{new_price / 100:.2f} "
        f"(was R{old_price / 100:.2f}, save R{drop / 100:.2f})"
    )
    payload = {
        "product_id": str(product.id),
        "store_id": str(store.id),
        "old_price": old_price,
        "new_price": new_price,
    }
    return Notification.objects.bulk_create(
        [
            Notification(
                user_id=user_id,
                kind=NotificationKind.PRICE_DROP,
                title=title,
                body=body,
                payload=payload,
            )
            for user_id in user_ids
        ]
    )
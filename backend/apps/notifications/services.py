"""Bridge price intelligence events into the in-app feed (TC-5.5) + FCM (M8)."""


def create_price_drop_notifications(product, store, old_price, new_price, user_ids):
    """Creates one in-app notification per affected list owner, then enqueues FCM."""
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
    created = Notification.objects.bulk_create(
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

    # M8: fire-and-forget push; no-ops without FCM_SERVER_KEY / devices.
    try:
        from apps.devices.tasks import send_fcm_price_drop

        send_fcm_price_drop.delay(
            user_ids=[str(uid) for uid in user_ids],
            title=title,
            body=body,
            payload=payload,
        )
    except Exception:  # noqa: BLE001
        # Never fail reconciliation because push dispatch failed.
        pass

    return created

"""Broadcast delivery quote updates (API Specification §9: ws /lists/{id}/delivery)."""
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer


def broadcast_delivery_event(list_id, event, payload):
    channel_layer = get_channel_layer()
    if channel_layer is None:
        return
    async_to_sync(channel_layer.group_send)(
        f"delivery_{list_id}",
        {"type": "delivery.event", "event": event, "payload": payload},
    )


def notify_availability_changed(product_id):
    """Fan out availability.changed to every list containing this product."""
    from apps.lists.models import ShoppingList

    list_ids = (
        ShoppingList.objects.filter(items__product_id=product_id)
        .values_list("id", flat=True)
        .distinct()
    )
    payload = {"product_id": str(product_id)}
    for list_id in list_ids:
        broadcast_delivery_event(list_id, "availability.changed", payload)
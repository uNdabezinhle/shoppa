"""Broadcasts chat events to WebSocket subscribers (SRS FR-3.4)."""
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer


def broadcast_chat_event(list_id, event, payload):
    channel_layer = get_channel_layer()
    if channel_layer is None:
        return
    async_to_sync(channel_layer.group_send)(
        f"chat_{list_id}",
        {"type": "chat.event", "event": event, "payload": payload},
    )
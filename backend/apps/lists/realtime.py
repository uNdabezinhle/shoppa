"""Broadcasts list mutations to WebSocket subscribers (SRS FR-3.2,
API Specification §9). Best-effort: if no channel layer is configured
this silently no-ops rather than breaking the REST request that
triggered it -- real-time propagation is an enhancement on top of the
REST CRUD, not a dependency of it.
"""
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer


def broadcast_list_event(list_id, event, payload):
    channel_layer = get_channel_layer()
    if channel_layer is None:
        return
    async_to_sync(channel_layer.group_send)(
        f"list_{list_id}",
        {"type": "list.event", "event": event, "payload": payload},
    )

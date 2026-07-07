"""Real-time delivery quote channel (API Specification §9: ws /lists/{id}/delivery).

Server -> client push only. Clients refresh quotes on quote.updated or
availability.changed events.
"""
from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncJsonWebsocketConsumer

from apps.lists.models import ShoppingList


class DeliveryConsumer(AsyncJsonWebsocketConsumer):
    async def connect(self):
        self.list_id = self.scope["url_route"]["kwargs"]["list_id"]
        self.group_name = f"delivery_{self.list_id}"
        user = self.scope.get("user")

        if user is None or not user.is_authenticated:
            await self.close(code=4001)
            return

        if not await self._has_access(user):
            await self.close(code=4004)
            return

        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()

    async def disconnect(self, code):
        if hasattr(self, "group_name"):
            await self.channel_layer.group_discard(self.group_name, self.channel_name)

    async def delivery_event(self, message):
        await self.send_json(
            {"event": message["event"], "payload": message["payload"]}
        )

    @database_sync_to_async
    def _has_access(self, user):
        list_obj = ShoppingList.objects.filter(pk=self.list_id).first()
        return list_obj is not None and list_obj.role_for(user) is not None
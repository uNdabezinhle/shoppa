"""Real-time list collaboration (SRS FR-3.2, API Specification §9:
ws /lists/{id}). This is a server -> client push channel only -- there is
no client -> server message protocol here; REST calls remain the only way
to mutate a list. REST views call broadcast_list_event() (realtime.py)
after each mutation, which fans the event out to every connected socket
in the list's group.
"""
from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncJsonWebsocketConsumer

from .models import ShoppingList
from .presence import active_users, user_joined, user_left


class ListConsumer(AsyncJsonWebsocketConsumer):
    async def connect(self):
        self.list_id = self.scope["url_route"]["kwargs"]["list_id"]
        self.group_name = f"list_{self.list_id}"
        user = self.scope.get("user")

        if user is None or not user.is_authenticated:
            await self.close(code=4001)
            return

        if not await self._has_access(user):
            # 404-equivalent for WebSockets: don't distinguish "list
            # doesn't exist" from "you have no role on it", matching the
            # no-existence-leak convention used by the REST endpoints.
            await self.close(code=4004)
            return

        self._user = user
        await self.channel_layer.group_add(self.group_name, self.channel_name)
        await self.accept()
        await database_sync_to_async(user_joined)(self.list_id, user)
        # Tell this socket who was already present (they missed those
        # join broadcasts).
        others = await database_sync_to_async(
            lambda: [
                payload
                for payload in active_users(self.list_id)
                if payload["user_id"] != str(user.id)
            ]
        )()
        for payload in others:
            await self.send_json({"event": "presence.joined", "payload": payload})

    async def disconnect(self, code):
        if hasattr(self, "group_name"):
            await self.channel_layer.group_discard(self.group_name, self.channel_name)
        if hasattr(self, "_user"):
            await database_sync_to_async(user_left)(self.list_id, self._user)

    async def list_event(self, message):
        """Handler name matches group_send's "type" ("list.event" ->
        "list_event"), per Channels' dispatch convention."""
        await self.send_json({"event": message["event"], "payload": message["payload"]})

    @database_sync_to_async
    def _has_access(self, user):
        list_obj = ShoppingList.objects.filter(pk=self.list_id).first()
        return list_obj is not None and list_obj.role_for(user) is not None

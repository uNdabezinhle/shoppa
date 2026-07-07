"""Tests for ListConsumer itself (SRS FR-3.2, API Specification §9:
ws /lists/{id}) -- connection auth/authorization and event relay. The
REST-side "does the right event get broadcast" wiring is covered by
RealtimeBroadcastTests in tests.py; here we drive the actual ASGI
consumer with Channels' WebsocketCommunicator.

Uses TransactionTestCase (not TestCase) because ListConsumer's
database_sync_to_async calls run on a separate thread with their own DB
connection, which needs a real committed row to see -- TestCase wraps
each test in an outer atomic block that a second thread can't see into.
"""
from channels.layers import get_channel_layer
from channels.routing import URLRouter
from channels.testing import WebsocketCommunicator
from django.test import TransactionTestCase
from rest_framework_simplejwt.tokens import RefreshToken

from apps.users.models import User

from .middleware import JWTAuthMiddlewareStack
from .models import CollaboratorPermission, ListCategory, ListCollaborator, ShoppingList
from .routing import websocket_urlpatterns

# Wraps the real routing + JWT auth middleware, same as shoppa_api/asgi.py's
# production wiring, so scope["url_route"] and scope["user"] are populated
# the same way a real client's connection would see them.
_application = JWTAuthMiddlewareStack(URLRouter(websocket_urlpatterns))


def _access_token_for(user):
    return str(RefreshToken.for_user(user).access_token)


class ListConsumerTests(TransactionTestCase):
    def setUp(self):
        self.owner = User.objects.create_user(
            username="ws-owner@example.com",
            email="ws-owner@example.com",
            password="a-strong-passw0rd!",
        )
        self.stranger = User.objects.create_user(
            username="ws-stranger@example.com",
            email="ws-stranger@example.com",
            password="a-strong-passw0rd!",
        )
        self.list = ShoppingList.objects.create(
            owner=self.owner, title="Braai", category=ListCategory.GROCERIES
        )

    def _communicator(self, token=None):
        path = f"/ws/lists/{self.list.id}/"
        if token:
            path += f"?token={token}"
        return WebsocketCommunicator(_application, path)

    async def test_connect_without_token_is_rejected(self):
        communicator = self._communicator()
        connected, _ = await communicator.connect()
        self.assertFalse(connected)
        await communicator.disconnect()

    async def test_connect_as_non_collaborator_is_rejected(self):
        token = _access_token_for(self.stranger)
        communicator = self._communicator(token)
        connected, _ = await communicator.connect()
        self.assertFalse(connected)
        await communicator.disconnect()

    async def test_owner_can_connect_and_receives_broadcast_events(self):
        token = _access_token_for(self.owner)
        communicator = self._communicator(token)
        connected, _ = await communicator.connect()
        self.assertTrue(connected)

        channel_layer = get_channel_layer()
        await channel_layer.group_send(
            f"list_{self.list.id}",
            {
                "type": "list.event",
                "event": "item.added",
                "payload": {"id": "abc", "name": "Boerewors"},
            },
        )

        message = await communicator.receive_json_from()
        self.assertEqual(message["event"], "item.added")
        self.assertEqual(message["payload"]["name"], "Boerewors")

        await communicator.disconnect()

    async def test_edit_collaborator_can_connect(self):
        friend = await self._create_collaborator()
        token = _access_token_for(friend)
        communicator = self._communicator(token)
        connected, _ = await communicator.connect()
        self.assertTrue(connected)
        await communicator.disconnect()

    async def test_connect_broadcasts_presence_joined_to_other_subscriber(self):
        friend = await self._create_collaborator()
        owner_token = _access_token_for(self.owner)
        friend_token = _access_token_for(friend)

        owner_comm = self._communicator(owner_token)
        self.assertTrue((await owner_comm.connect())[0])

        friend_comm = self._communicator(friend_token)
        self.assertTrue((await friend_comm.connect())[0])

        message = await owner_comm.receive_json_from()
        self.assertEqual(message["event"], "presence.joined")
        self.assertEqual(message["payload"]["email"], "ws-friend@example.com")

        await friend_comm.disconnect()
        left = await owner_comm.receive_json_from()
        self.assertEqual(left["event"], "presence.left")
        self.assertEqual(left["payload"]["user_id"], str(friend.id))

        await owner_comm.disconnect()

    async def _create_collaborator(self):
        from channels.db import database_sync_to_async

        @database_sync_to_async
        def create():
            friend = User.objects.create_user(
                username="ws-friend@example.com",
                email="ws-friend@example.com",
                password="a-strong-passw0rd!",
            )
            ListCollaborator.objects.create(
                list=self.list, user=friend, permission=CollaboratorPermission.EDIT
            )
            return friend

        return await create()

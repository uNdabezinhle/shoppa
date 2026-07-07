"""TC-3.2: edit propagation reaches subscribers within 1 second (SRS FR-3.2).

Drives the full stack — REST mutation -> broadcast_list_event -> channel
layer -> ListConsumer — rather than mocking the broadcast hook.
"""
import asyncio
import time

from channels.db import database_sync_to_async
from channels.routing import URLRouter
from channels.testing import WebsocketCommunicator
from django.test import TransactionTestCase
from django.urls import reverse
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken

from apps.users.models import User

from .middleware import JWTAuthMiddlewareStack
from .models import ListCategory, ListItem, ShoppingList
from .routing import websocket_urlpatterns

_application = JWTAuthMiddlewareStack(URLRouter(websocket_urlpatterns))


def _access_token_for(user):
    return str(RefreshToken.for_user(user).access_token)


class PropagationPerfTests(TransactionTestCase):
    def setUp(self):
        self.owner = User.objects.create_user(
            username="prop-owner@example.com",
            email="prop-owner@example.com",
            password="a-strong-passw0rd!",
        )
        self.list = ShoppingList.objects.create(
            owner=self.owner, title="Propagation", category=ListCategory.GROCERIES
        )
        self.item = ListItem.objects.create(list=self.list, name="Milk")

    def _communicator(self, token):
        path = f"/ws/lists/{self.list.id}/?token={token}"
        return WebsocketCommunicator(_application, path)

    async def _drain_socket(self, communicator, seconds=0.3):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            try:
                await asyncio.wait_for(communicator.receive_json_from(), timeout=0.05)
            except asyncio.TimeoutError:
                break

    def _patch_item_name(self):
        client = APIClient()
        client.force_authenticate(self.owner)
        url = reverse(
            "list-items-detail",
            kwargs={"list_id": self.list.id, "item_id": self.item.id},
        )
        response = client.patch(url, {"name": "Low-fat milk"}, format="json")
        assert response.status_code == 200

    async def test_item_update_reaches_subscriber_within_one_second(self):
        """TC-3.2: REST edit fans out to an open WebSocket in < 1 s."""
        token = _access_token_for(self.owner)
        communicator = self._communicator(token)
        connected, _ = await communicator.connect()
        self.assertTrue(connected)

        await self._drain_socket(communicator)

        started = time.monotonic()
        await database_sync_to_async(self._patch_item_name)()
        message = await asyncio.wait_for(communicator.receive_json_from(), timeout=1.0)
        elapsed = time.monotonic() - started

        self.assertEqual(message["event"], "item.updated")
        self.assertEqual(message["payload"]["name"], "Low-fat milk")
        self.assertLess(elapsed, 1.0)

        await communicator.disconnect()
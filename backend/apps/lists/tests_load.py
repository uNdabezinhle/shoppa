"""Channels fan-out load probe for the M2 gate (Implementation Plan §6.2).

Verifies that N concurrent WebSocket subscribers on the same list all
receive a broadcast promptly. Uses the in-memory channel layer in CI;
point REDIS_URL at Redis for staging runs that mirror production.
"""
import asyncio
import time

from channels.layers import get_channel_layer
from channels.routing import URLRouter
from channels.testing import WebsocketCommunicator
from django.test import TransactionTestCase
from rest_framework_simplejwt.tokens import RefreshToken

from apps.users.models import User

from .middleware import JWTAuthMiddlewareStack
from .models import ListCategory, ShoppingList
from .routing import websocket_urlpatterns

_application = JWTAuthMiddlewareStack(URLRouter(websocket_urlpatterns))

# M2 gate target — matches Implementation Plan load-test guidance.
_SUBSCRIBER_COUNT = 32
_FANOUT_DEADLINE_SECONDS = 2.0


def _access_token_for(user):
    return str(RefreshToken.for_user(user).access_token)


class ChannelsLoadTests(TransactionTestCase):
    def setUp(self):
        self.owner = User.objects.create_user(
            username="load-owner@example.com",
            email="load-owner@example.com",
            password="a-strong-passw0rd!",
        )
        self.list = ShoppingList.objects.create(
            owner=self.owner, title="Load test", category=ListCategory.CUSTOM
        )

    def _communicator(self, token):
        path = f"/ws/lists/{self.list.id}/?token={token}"
        return WebsocketCommunicator(_application, path)

    async def _drain_socket(self, communicator, seconds=0.2):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            try:
                await asyncio.wait_for(communicator.receive_json_from(), timeout=0.05)
            except asyncio.TimeoutError:
                break

    async def test_concurrent_subscribers_all_receive_broadcast(self):
        token = _access_token_for(self.owner)
        communicators = [self._communicator(token) for _ in range(_SUBSCRIBER_COUNT)]

        for comm in communicators:
            connected, _ = await comm.connect()
            self.assertTrue(connected)
            await self._drain_socket(comm)

        channel_layer = get_channel_layer()
        started = time.monotonic()
        await channel_layer.group_send(
            f"list_{self.list.id}",
            {
                "type": "list.event",
                "event": "item.added",
                "payload": {"id": "probe", "name": "Load probe"},
            },
        )

        received = 0
        for comm in communicators:
            message = await asyncio.wait_for(
                comm.receive_json_from(), timeout=_FANOUT_DEADLINE_SECONDS
            )
            self.assertEqual(message["event"], "item.added")
            received += 1

        elapsed = time.monotonic() - started
        self.assertEqual(received, _SUBSCRIBER_COUNT)
        self.assertLess(elapsed, _FANOUT_DEADLINE_SECONDS)

        for comm in communicators:
            await comm.disconnect()
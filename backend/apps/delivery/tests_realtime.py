"""Delivery WebSocket channel tests (API Specification §9)."""
from channels.db import database_sync_to_async
from channels.layers import get_channel_layer
from channels.routing import URLRouter
from channels.testing import WebsocketCommunicator
from django.test import TransactionTestCase
from rest_framework_simplejwt.tokens import RefreshToken

from apps.lists.middleware import JWTAuthMiddlewareStack
from apps.lists.models import ListCategory, ListItem, ShoppingList
from apps.price_intelligence.models import PriceSource, Product, Store
from apps.price_intelligence.services import record_observation
from apps.users.models import User

from .routing import websocket_urlpatterns

_application = JWTAuthMiddlewareStack(URLRouter(websocket_urlpatterns))


def _access_token_for(user):
    return str(RefreshToken.for_user(user).access_token)


class DeliveryConsumerTests(TransactionTestCase):
    def setUp(self):
        self.owner = User.objects.create_user(
            username="delivery-ws@example.com",
            email="delivery-ws@example.com",
            password="a-strong-passw0rd!",
            region="ZA",
        )
        self.stranger = User.objects.create_user(
            username="stranger-ws@example.com",
            email="stranger-ws@example.com",
            password="a-strong-passw0rd!",
            region="ZA",
        )
        self.list = ShoppingList.objects.create(
            owner=self.owner, title="Delivery", category=ListCategory.GROCERIES
        )
        self.milk = Product.objects.create(name="Full Cream Milk 2L", region="ZA")
        ListItem.objects.create(
            list=self.list, name=self.milk.name, product_id=self.milk.id, quantity=1
        )
        self.store = Store.objects.create(name="Checkers", region="ZA")

    def _communicator(self, token=None):
        path = f"/ws/lists/{self.list.id}/delivery/"
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

    async def test_owner_receives_quote_updated_broadcast(self):
        token = _access_token_for(self.owner)
        communicator = self._communicator(token)
        connected, _ = await communicator.connect()
        self.assertTrue(connected)

        channel_layer = get_channel_layer()
        payload = {
            "currency_code": "ZAR",
            "quotes": [{"platform": "checkers_6060", "total": 7598}],
        }
        await channel_layer.group_send(
            f"delivery_{self.list.id}",
            {
                "type": "delivery.event",
                "event": "quote.updated",
                "payload": payload,
            },
        )

        response = await communicator.receive_json_from()
        self.assertEqual(response["event"], "quote.updated")
        self.assertEqual(response["payload"]["currency_code"], "ZAR")
        await communicator.disconnect()

    async def test_price_reconcile_broadcasts_availability_changed(self):
        token = _access_token_for(self.owner)
        communicator = self._communicator(token)
        connected, _ = await communicator.connect()
        self.assertTrue(connected)

        await database_sync_to_async(record_observation)(
            product=self.milk,
            store=self.store,
            price=3299,
            source=PriceSource.STORE,
        )

        response = await communicator.receive_json_from()
        self.assertEqual(response["event"], "availability.changed")
        self.assertEqual(response["payload"]["product_id"], str(self.milk.id))
        await communicator.disconnect()
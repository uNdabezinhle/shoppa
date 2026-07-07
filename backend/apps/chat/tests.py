"""Per-list chat tests (SRS FR-3.4, QA Test Plan TC-3.4)."""
from channels.layers import get_channel_layer
from channels.routing import URLRouter
from channels.testing import WebsocketCommunicator
from django.test import TransactionTestCase
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase
from rest_framework_simplejwt.tokens import RefreshToken

from apps.lists.models import CollaboratorPermission, ListCategory, ListCollaborator, ShoppingList
from apps.users.models import User

from apps.lists.middleware import JWTAuthMiddlewareStack
from .models import ListChatMessage
from .routing import websocket_urlpatterns

_application = JWTAuthMiddlewareStack(URLRouter(websocket_urlpatterns))


def _access_token_for(user):
    return str(RefreshToken.for_user(user).access_token)


class ListChatRestTests(APITestCase):
    def setUp(self):
        self.owner = User.objects.create_user(
            username="owner@example.com",
            email="owner@example.com",
            password="a-strong-passw0rd!",
        )
        self.friend = User.objects.create_user(
            username="friend@example.com",
            email="friend@example.com",
            password="a-strong-passw0rd!",
        )
        self.stranger = User.objects.create_user(
            username="stranger@example.com",
            email="stranger@example.com",
            password="a-strong-passw0rd!",
        )
        self.list = ShoppingList.objects.create(
            owner=self.owner, title="Braai", category=ListCategory.GROCERIES
        )
        ListCollaborator.objects.create(
            list=self.list, user=self.friend, permission=CollaboratorPermission.EDIT
        )
        self.url = reverse("list-messages", kwargs={"list_id": self.list.id})

    def _auth(self, user):
        token = _access_token_for(user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")

    def test_collaborator_can_post_and_fetch_messages(self):
        self._auth(self.friend)
        response = self.client.post(self.url, {"body": "On my way!"}, format="json")
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["body"], "On my way!")
        self.assertEqual(response.data["author_email"], "friend@example.com")

        history = self.client.get(self.url)
        self.assertEqual(history.status_code, status.HTTP_200_OK)
        self.assertEqual(len(history.data["results"]), 1)

    def test_stranger_cannot_access_messages(self):
        self._auth(self.stranger)
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_empty_body_is_rejected(self):
        self._auth(self.owner)
        response = self.client.post(self.url, {"body": "   "}, format="json")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)


class ChatConsumerTests(TransactionTestCase):
    def setUp(self):
        self.owner = User.objects.create_user(
            username="chat-owner@example.com",
            email="chat-owner@example.com",
            password="a-strong-passw0rd!",
        )
        self.stranger = User.objects.create_user(
            username="chat-stranger@example.com",
            email="chat-stranger@example.com",
            password="a-strong-passw0rd!",
        )
        self.list = ShoppingList.objects.create(
            owner=self.owner, title="Chat list", category=ListCategory.CUSTOM
        )

    def _communicator(self, token=None):
        path = f"/ws/lists/{self.list.id}/chat/"
        if token:
            path += f"?token={token}"
        return WebsocketCommunicator(_application, path)

    async def test_stranger_cannot_connect_to_chat(self):
        token = _access_token_for(self.stranger)
        communicator = self._communicator(token)
        connected, _ = await communicator.connect()
        self.assertFalse(connected)
        await communicator.disconnect()

    async def test_owner_receives_message_created_broadcast(self):
        token = _access_token_for(self.owner)
        communicator = self._communicator(token)
        connected, _ = await communicator.connect()
        self.assertTrue(connected)

        channel_layer = get_channel_layer()
        await channel_layer.group_send(
            f"chat_{self.list.id}",
            {
                "type": "chat.event",
                "event": "message.created",
                "payload": {"id": "m-1", "body": "Hello"},
            },
        )

        message = await communicator.receive_json_from()
        self.assertEqual(message["event"], "message.created")
        self.assertEqual(message["payload"]["body"], "Hello")
        await communicator.disconnect()
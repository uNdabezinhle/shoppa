"""Per-list chat messages (SRS FR-3.4, API Specification §9)."""
import uuid

from django.conf import settings
from django.db import models


class ListChatMessage(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    list = models.ForeignKey(
        "lists.ShoppingList",
        on_delete=models.CASCADE,
        related_name="chat_messages",
    )
    author = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="list_chat_messages",
    )
    body = models.CharField(max_length=500)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["created_at"]

    def __str__(self):
        return f"{self.author} on {self.list}: {self.body[:40]}"
"""In-app notification feed (SRS FR-5.4 / TC-5.5).

Push delivery (FCM) is deferred; this model backs GET /v1/notifications
for price-drop and future notification kinds.
"""
import uuid

from django.conf import settings
from django.db import models


class NotificationKind(models.TextChoices):
    PRICE_DROP = "price_drop", "Price drop"


class Notification(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="notifications",
    )
    kind = models.CharField(max_length=30, choices=NotificationKind.choices)
    title = models.CharField(max_length=200)
    body = models.CharField(max_length=500)
    payload = models.JSONField(default=dict, blank=True)
    read_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.kind} for {self.user}: {self.title}"
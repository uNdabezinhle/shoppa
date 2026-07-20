"""Push device tokens for FCM (M8)."""
import uuid

from django.conf import settings
from django.db import models


class DevicePlatform(models.TextChoices):
    ANDROID = "android", "Android"
    IOS = "ios", "iOS"
    WEB = "web", "Web"


class Device(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="devices",
    )
    token = models.CharField(max_length=512)
    platform = models.CharField(
        max_length=20,
        choices=DevicePlatform.choices,
        default=DevicePlatform.ANDROID,
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = [("user", "token")]
        ordering = ["-updated_at"]

    def __str__(self):
        return f"{self.platform} device for {self.user_id}"

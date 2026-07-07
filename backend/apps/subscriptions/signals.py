from django.db.models.signals import post_save
from django.dispatch import receiver

from apps.users.models import User

from .services import ensure_user_subscription


@receiver(post_save, sender=User)
def assign_free_subscription(sender, instance, created, **kwargs):
    if created:
        ensure_user_subscription(instance)
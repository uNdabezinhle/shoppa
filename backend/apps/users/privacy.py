"""POPIA-oriented data portability and erasure (Implementation Plan §12)."""
from django.contrib.auth import authenticate
from django.db import transaction

from apps.lists.models import ShoppingList
from apps.subscriptions.services import get_active_subscription

from .models import User
from .serializers import UserSerializer


def build_user_data_export(user: User) -> dict:
    subscription = get_active_subscription(user)
    owned_lists = ShoppingList.objects.filter(owner=user).order_by("title")
    return {
        "user": UserSerializer(user).data,
        "subscription": {
            "plan_id": subscription.plan_id,
            "status": subscription.status,
        },
        "owned_lists": [
            {
                "id": str(lst.id),
                "title": lst.title,
                "category": lst.category,
                "item_count": lst.items.count(),
                "is_public": lst.is_public,
            }
            for lst in owned_lists
        ],
        "export_format": "shoppa-user-export-v1",
    }


@transaction.atomic
def delete_user_account(user: User, *, password: str) -> None:
    if not authenticate(username=user.email, password=password):
        raise ValueError("Invalid password.")
    user.delete()
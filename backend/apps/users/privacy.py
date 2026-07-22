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

    allergen_profile = None
    try:
        from apps.product_verify.models import ScanEvent, UserAllergenProfile

        try:
            profile = user.allergen_profile
            allergen_profile = {
                "allergens": profile.allergens or [],
                "consent_at": (
                    profile.consent_at.isoformat().replace("+00:00", "Z")
                    if profile.consent_at
                    else None
                ),
                "updated_at": profile.updated_at.isoformat().replace(
                    "+00:00", "Z"
                ),
            }
        except UserAllergenProfile.DoesNotExist:
            allergen_profile = None

        scan_history = [
            {
                "gtin": e.gtin,
                "level": e.level,
                "product_name": e.product_name,
                "scanned_at": e.scanned_at.isoformat().replace("+00:00", "Z"),
            }
            for e in ScanEvent.objects.filter(user=user)[:100]
        ]
    except Exception:
        scan_history = []

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
        "allergen_profile": allergen_profile,
        "scan_history": scan_history,
        "export_format": "shoppa-user-export-v1",
    }


@transaction.atomic
def delete_user_account(user: User, *, password: str) -> None:
    if not authenticate(username=user.email, password=password):
        raise ValueError("Invalid password.")
    user.delete()
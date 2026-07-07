"""Admin console APIs (Phase 5): overview, moderation, partners."""
from django.db.models import Count
from django.shortcuts import get_object_or_404
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.lists.models import ShoppingList
from apps.price_intelligence.models import PriceObservation, Store
from apps.promotions.models import Promotion
from apps.subscriptions.models import UserSubscription
from apps.users.models import User

from .permissions import IsAdminUser


class AdminOverviewView(APIView):
    """GET /v1/admin/overview — aggregate platform health."""

    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def get(self, request):
        subscriptions = (
            UserSubscription.objects.filter(status=UserSubscription.Status.ACTIVE)
            .values("plan_id")
            .annotate(count=Count("id"))
        )
        return Response(
            {
                "users": User.objects.count(),
                "lists": ShoppingList.objects.count(),
                "quarantined_observations": PriceObservation.objects.filter(
                    is_quarantined=True
                ).count(),
                "stores": Store.objects.count(),
                "active_promotions": Promotion.objects.filter(is_active=True).count(),
                "subscriptions_by_plan": {
                    row["plan_id"]: row["count"] for row in subscriptions
                },
            }
        )


class ModerationQueueView(APIView):
    """GET /v1/admin/moderation/quarantine — price observation review queue."""

    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def get(self, request):
        observations = (
            PriceObservation.objects.filter(is_quarantined=True)
            .select_related("product", "store", "submitted_by")
            .order_by("-observed_at")[:50]
        )
        results = [
            {
                "id": str(obs.id),
                "product_name": obs.product.name,
                "store_name": obs.store.name,
                "price": obs.price,
                "source": obs.source,
                "submitted_by": obs.submitted_by.email if obs.submitted_by else None,
                "observed_at": obs.observed_at.isoformat(),
            }
            for obs in observations
        ]
        return Response({"results": results})


class ModerationActionView(APIView):
    """PATCH /v1/admin/moderation/quarantine/{id} — approve or reject."""

    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def patch(self, request, pk):
        action = request.data.get("action")
        if action not in {"approve", "reject"}:
            return Response(
                {
                    "error": {
                        "code": "validation_error",
                        "message": "action must be approve or reject.",
                    }
                },
                status=status.HTTP_422_UNPROCESSABLE_ENTITY,
            )

        observation = get_object_or_404(PriceObservation, pk=pk, is_quarantined=True)
        if action == "approve":
            observation.is_quarantined = False
            observation.save(update_fields=["is_quarantined"])
            from apps.price_intelligence.services import reconcile

            reconcile(observation.product, observation.store)
        else:
            observation.delete()

        return Response({"id": str(pk), "action": action, "status": "ok"})


class PartnerStoresView(APIView):
    """GET /v1/admin/partners/stores — partner directory for admin console."""

    permission_classes = [permissions.IsAuthenticated, IsAdminUser]

    def get(self, request):
        stores = Store.objects.annotate(
            promotion_count=Count("promotions")
        ).order_by("name")
        results = [
            {
                "id": str(store.id),
                "name": store.name,
                "region": store.region,
                "promotion_count": store.promotion_count,
            }
            for store in stores
        ]
        return Response({"results": results})
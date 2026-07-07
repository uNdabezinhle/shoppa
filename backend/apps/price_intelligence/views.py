"""FR-5.1 ingestion endpoint and price-history read endpoint (API
Specification §6.4).
"""
from django.utils import timezone
from rest_framework import generics, permissions
from rest_framework.pagination import CursorPagination

from .models import PriceObservation, PriceSource
from .serializers import PriceHistoryEntrySerializer, PriceObservationSerializer
from .services import record_observation


class PriceObservationCreateView(generics.CreateAPIView):
    """POST /v1/prices/observations -- a crowd-sourced submission (FR-5.1).
    Routed through services.record_observation so this shares exactly one
    ingestion/reconciliation code path with the implicit observation
    created on item check-off (apps.lists views).
    """

    serializer_class = PriceObservationSerializer
    permission_classes = [permissions.IsAuthenticated]

    def perform_create(self, serializer):
        validated = serializer.validated_data
        observation = record_observation(
            product=validated["product"],
            store=validated["store"],
            price=validated["price"],
            source=PriceSource.CROWD,
            observed_at=validated.get("observed_at") or timezone.now(),
            submitted_by=self.request.user,
        )
        serializer.instance = observation


class PriceHistoryCursorPagination(CursorPagination):
    ordering = "-observed_at"
    page_size = 30


class ProductPriceHistoryView(generics.ListAPIView):
    """GET /v1/products/{id}/price-history -- excludes quarantined
    observations (TC-5.3: a quarantined outlier must not surface to
    clients).
    """

    serializer_class = PriceHistoryEntrySerializer
    permission_classes = [permissions.IsAuthenticated]
    pagination_class = PriceHistoryCursorPagination

    def get_queryset(self):
        return (
            PriceObservation.objects.filter(
                product_id=self.kwargs["product_id"], is_quarantined=False
            )
            .select_related("store")
            .order_by("-observed_at")
        )

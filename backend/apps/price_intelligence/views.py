"""FR-5.1 ingestion endpoint and price-history read endpoint (API
Specification §6.4).
"""
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import generics, permissions
from rest_framework.pagination import CursorPagination
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import CurrentPrice, PriceObservation, PriceSource, Product
from .serializers import (
    PriceHistoryEntrySerializer,
    PriceObservationSerializer,
    ProductSerializer,
    ProductStorePriceSerializer,
)
from .services import record_observation


class ProductSearchPagination(CursorPagination):
    ordering = "name"
    page_size = 20


class ProductSearchView(generics.ListAPIView):
    """GET /v1/products?q= — region-scoped catalogue search (M3 / FR-5.3).

    DB-backed for now; Typesense integration can replace the queryset
    filter without changing the response shape.
    """

    serializer_class = ProductSerializer
    permission_classes = [permissions.IsAuthenticated]
    pagination_class = ProductSearchPagination

    def get_queryset(self):
        region = getattr(self.request.user, "region", "ZA") or "ZA"
        qs = Product.objects.filter(region=region)
        query = self.request.query_params.get("q", "").strip()
        if query:
            qs = qs.filter(name__icontains=query)
        return qs.order_by("name")


class ProductStorePriceView(APIView):
    """GET /v1/products/{id}/store-price?store_id= — current reconciled
    price for shop-mode check-off prefill (M3 / FR-5.4).
    """

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, product_id):
        store_id = request.query_params.get("store_id")
        if not store_id:
            return Response(
                {
                    "error": {
                        "code": "validation_error",
                        "message": "store_id query parameter is required.",
                    }
                },
                status=400,
            )
        product = get_object_or_404(Product, pk=product_id)
        region = getattr(request.user, "region", "ZA") or "ZA"
        if product.region != region:
            return Response(status=404)
        current = CurrentPrice.objects.filter(
            product_id=product_id, store_id=store_id
        ).first()
        if current is None:
            return Response(status=404)
        return Response(
            ProductStorePriceSerializer(
                {
                    "store_id": current.store_id,
                    "price": current.price,
                    "confidence": current.confidence,
                }
            ).data
        )


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

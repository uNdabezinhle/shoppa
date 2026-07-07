"""Advertising APIs (API Specification §6.8, SRS FR-10.1–FR-10.6)."""
from django.shortcuts import get_object_or_404
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import AdPlacement
from .serializers import AdClickSerializer, AdImpressionSerializer
from .services import (
    get_placements,
    placement_payload,
    record_click,
    record_impression,
    user_sees_ads,
)


class AdPlacementsView(APIView):
    """GET /v1/ads/placements — eligible house creatives for a surface."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        surface = request.query_params.get("surface", "").lower()
        if surface not in {"home", "list", "checkout"}:
            return Response(
                {
                    "error": {
                        "code": "validation_error",
                        "message": "surface must be home, list, or checkout.",
                    }
                },
                status=status.HTTP_422_UNPROCESSABLE_ENTITY,
            )

        ad_format = request.query_params.get("ad_format")
        if ad_format is not None:
            ad_format = ad_format.lower()
            if ad_format not in {"banner", "native", "interstitial", "rewarded"}:
                return Response(
                    {
                        "error": {
                            "code": "validation_error",
                            "message": "ad_format is invalid.",
                        }
                    },
                    status=status.HTTP_422_UNPROCESSABLE_ENTITY,
                )

        session_key = request.query_params.get("session_key", "")
        placements = get_placements(
            request.user,
            surface=surface,
            ad_format=ad_format,
            session_key=session_key,
        )
        return Response(
            {
                "results": [placement_payload(p) for p in placements],
                "ads_free": not user_sees_ads(request.user),
            }
        )


class AdImpressionView(APIView):
    """POST /v1/ads/impressions — record a show event (no-op for ads_free)."""

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        serializer = AdImpressionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data

        if not user_sees_ads(request.user):
            return Response({"recorded": False, "reason": "ads_free"})

        placement = get_object_or_404(AdPlacement, pk=data["placement_id"], is_active=True)
        impression = record_impression(
            request.user,
            placement,
            surface=data["surface"],
            ad_format=data["ad_format"],
            session_key=data.get("session_key", ""),
        )
        if impression is None:
            return Response({"recorded": False, "reason": "frequency_cap"})
        return Response(
            {"recorded": True, "id": str(impression.id)},
            status=status.HTTP_201_CREATED,
        )


class AdClickView(APIView):
    """POST /v1/ads/clicks — record a click-through (no-op for ads_free)."""

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        serializer = AdClickSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        if not user_sees_ads(request.user):
            return Response({"recorded": False, "reason": "ads_free"})

        placement = get_object_or_404(
            AdPlacement, pk=serializer.validated_data["placement_id"], is_active=True
        )
        click = record_click(request.user, placement)
        return Response(
            {"recorded": True, "id": str(click.id)},
            status=status.HTTP_201_CREATED,
        )
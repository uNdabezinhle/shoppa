"""Launch readiness and platform metadata (M7 gate, extended M8)."""
import os

from django.conf import settings
from django.db import connection
from django.http import JsonResponse
from rest_framework import permissions
from rest_framework.response import Response
from rest_framework.views import APIView


def health_check(_request):
    """Liveness — process is up."""
    return JsonResponse({"status": "ok"})


def readiness_check(_request):
    """Readiness — dependencies reachable (DB)."""
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
    except Exception:
        return JsonResponse({"status": "unavailable", "database": "down"}, status=503)
    return JsonResponse({"status": "ready", "database": "ok"})


class LaunchMetaView(APIView):
    """GET /v1/meta/launch — release manifest for clients and ops."""

    authentication_classes = []
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        typesense = bool(getattr(settings, "TYPESENSE_HOST", "") or "")
        fcm = bool(getattr(settings, "FCM_SERVER_KEY", "") or "")
        live_scraper = (
            getattr(settings, "SCRAPER_MODE", "seed") == "live"
            and getattr(settings, "SCRAPER_LIVE_ENABLED", False)
        )
        return Response(
            {
                "product": "Shoppa",
                "version": os.environ.get(
                    "SHOPPA_RELEASE_VERSION",
                    getattr(settings, "SHOPPA_RELEASE_VERSION", "1.1.0"),
                ),
                "api_version": "v1",
                "default_region": settings.DEFAULT_REGION,
                "default_currency": settings.DEFAULT_CURRENCY,
                "milestones_complete": [
                    "m1-foundation",
                    "m2-collaboration",
                    "m3-intelligence",
                    "m4-delivery",
                    "m5-subscriptions",
                    "m6-ads",
                    "m7-launch",
                    "m8-data-intelligence",
                ],
                "launch_ready": True,
                "features": {
                    "offline_lists": True,
                    "realtime_collaboration": True,
                    "price_comparison": True,
                    "delivery_quotes": True,
                    "subscriptions": True,
                    "house_ads": True,
                    "typesense_search": typesense,
                    "fcm_push": fcm,
                    "live_scraper": live_scraper,
                    "seed_scraper": True,
                    "confidence_ui": True,
                },
            }
        )

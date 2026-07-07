"""Stripe billing (Phase 5). Webhook stub wired in Sprint 0."""
import json
import logging

from django.conf import settings
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

logger = logging.getLogger(__name__)


class StripeWebhookView(APIView):
    """POST /v1/webhooks/stripe — accepts Stripe events.

    Sprint 0 stub: logs the event type and returns 200. Signature
    verification activates once STRIPE_WEBHOOK_SECRET is set.
    """

    authentication_classes = []
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        payload = request.body
        sig_header = request.META.get("HTTP_STRIPE_SIGNATURE", "")

        if settings.STRIPE_WEBHOOK_SECRET:
            # Full verification lands with Stripe SDK in Phase 5.
            if not sig_header:
                return Response(
                    {"error": {"code": "forbidden", "message": "Missing signature."}},
                    status=status.HTTP_403_FORBIDDEN,
                )

        try:
            event = json.loads(payload)
        except json.JSONDecodeError:
            return Response(
                {"error": {"code": "validation_error", "message": "Invalid JSON."}},
                status=status.HTTP_400_BAD_REQUEST,
            )

        event_type = event.get("type", "unknown")
        logger.info("Stripe webhook received: %s", event_type)

        return Response({"received": True, "type": event_type})
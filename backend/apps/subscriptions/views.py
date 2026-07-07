"""Stripe billing and subscription APIs (SRS FR-9.1–FR-9.2, API §6.7)."""
import json
import logging

from django.conf import settings
from django.shortcuts import get_object_or_404
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import SubscriptionPlan
from .serializers import SubscriptionPlanSerializer, UserSubscriptionSerializer
from .services import (
    create_checkout_session,
    ensure_plans_seeded,
    get_active_subscription,
    handle_checkout_completed,
)

logger = logging.getLogger(__name__)


class SubscriptionPlansView(APIView):
    """GET /v1/subscriptions/plans"""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        ensure_plans_seeded()
        plans = SubscriptionPlan.objects.filter(is_active=True)
        return Response(
            {"results": SubscriptionPlanSerializer(plans, many=True).data}
        )


class SubscriptionMeView(APIView):
    """GET /v1/subscriptions/me"""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        subscription = get_active_subscription(request.user)
        return Response(UserSubscriptionSerializer(subscription).data)


class SubscriptionCheckoutView(APIView):
    """POST /v1/subscriptions/checkout"""

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        plan_id = request.data.get("plan_id")
        if not plan_id:
            return Response(
                {
                    "error": {
                        "code": "validation_error",
                        "message": "plan_id is required.",
                    }
                },
                status=status.HTTP_422_UNPROCESSABLE_ENTITY,
            )
        ensure_plans_seeded()
        plan = get_object_or_404(SubscriptionPlan, slug=plan_id, is_active=True)
        if plan.price_monthly <= 0:
            return Response(
                {
                    "error": {
                        "code": "validation_error",
                        "message": "Cannot purchase the free plan.",
                    }
                },
                status=status.HTTP_422_UNPROCESSABLE_ENTITY,
            )
        try:
            session = create_checkout_session(request.user, plan)
        except ValueError as exc:
            return Response(
                {"error": {"code": "validation_error", "message": str(exc)}},
                status=status.HTTP_422_UNPROCESSABLE_ENTITY,
            )
        return Response(session)


class StripeWebhookView(APIView):
    """POST /v1/webhooks/stripe — reconciles subscription state (FR-9.2)."""

    authentication_classes = []
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        payload = request.body
        sig_header = request.META.get("HTTP_STRIPE_SIGNATURE", "")

        if settings.STRIPE_WEBHOOK_SECRET:
            if not sig_header:
                return Response(
                    {"error": {"code": "forbidden", "message": "Missing signature."}},
                    status=status.HTTP_403_FORBIDDEN,
                )
            try:
                import stripe

                stripe.api_key = settings.STRIPE_SECRET_KEY
                event = stripe.Webhook.construct_event(
                    payload, sig_header, settings.STRIPE_WEBHOOK_SECRET
                )
            except Exception:
                return Response(
                    {"error": {"code": "forbidden", "message": "Invalid signature."}},
                    status=status.HTTP_403_FORBIDDEN,
                )
        else:
            try:
                event = json.loads(payload)
            except json.JSONDecodeError:
                return Response(
                    {
                        "error": {
                            "code": "validation_error",
                            "message": "Invalid JSON.",
                        }
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )

        event_type = event.get("type", "unknown")
        logger.info("Stripe webhook received: %s", event_type)

        if event_type == "checkout.session.completed":
            handle_checkout_completed(event.get("data", {}).get("object", {}))

        return Response({"received": True, "type": event_type})
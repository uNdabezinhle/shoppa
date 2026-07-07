"""FR-7.1 (GET /promotions) and FR-7.3 (POST /promotions/opt-out), API
Specification §6.6.
"""
from rest_framework import generics, permissions, status
from rest_framework.pagination import CursorPagination
from rest_framework.response import Response

from .models import PromotionOptOut
from .serializers import PromotionOptOutSerializer, PromotionSerializer
from .services import active_promotions_for_user


class PromotionCursorPagination(CursorPagination):
    ordering = "-created_at"
    page_size = 20


class PromotionListView(generics.ListAPIView):
    """GET /v1/promotions: promotions matched to the caller's list
    contents, minus anything they've opted out of (FR-7.1, FR-7.3)."""

    serializer_class = PromotionSerializer
    permission_classes = [permissions.IsAuthenticated]
    pagination_class = PromotionCursorPagination

    def get_queryset(self):
        return active_promotions_for_user(self.request.user)


class PromotionOptOutView(generics.CreateAPIView):
    """POST /v1/promotions/opt-out (FR-7.3). Idempotent: opting out of
    the same store/category twice is a no-op, not a 409/500 -- a user
    retrying (or an app re-sending after a flaky response) shouldn't see
    an error for something that's already true.
    """

    serializer_class = PromotionOptOutSerializer
    permission_classes = [permissions.IsAuthenticated]

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        store = serializer.validated_data.get("store")
        category = serializer.validated_data.get("category", "")

        lookup = {"user": request.user}
        if store:
            lookup["store"] = store
        else:
            lookup["category"] = category
        opt_out, _ = PromotionOptOut.objects.get_or_create(**lookup)

        return Response(
            PromotionOptOutSerializer(opt_out).data, status=status.HTTP_201_CREATED
        )

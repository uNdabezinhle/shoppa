"""GET /v1/lists/{id}/delivery-quotes (API Specification §6.5)."""
from rest_framework import permissions
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.lists.views import SharedListMixin

from .services import get_delivery_quotes_for_list


class ListDeliveryQuotesView(SharedListMixin, APIView):
    """FR-6.2: compare delivery prices and ETAs for a list."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, list_id):
        list_obj = self.get_list()
        return Response(get_delivery_quotes_for_list(list_obj))
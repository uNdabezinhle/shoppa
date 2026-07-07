"""Per-list chat REST endpoints (SRS FR-3.4).

GET/POST /lists/{id}/messages — history and send. Messages are also
pushed to ws /lists/{id}/chat subscribers via broadcast_chat_event().
"""
from django.http import Http404
from django.shortcuts import get_object_or_404
from rest_framework import generics, permissions
from rest_framework.pagination import CursorPagination

from apps.lists.models import ShoppingList

from .models import ListChatMessage
from .realtime import broadcast_chat_event
from .serializers import ListChatMessageSerializer


class MessageCursorPagination(CursorPagination):
    ordering = "created_at"
    page_size = 50


class ListMessageListView(generics.ListCreateAPIView):
    serializer_class = ListChatMessageSerializer
    permission_classes = [permissions.IsAuthenticated]
    pagination_class = MessageCursorPagination

    def get_list(self):
        list_obj = get_object_or_404(ShoppingList, pk=self.kwargs["list_id"])
        if list_obj.role_for(self.request.user) is None:
            raise Http404
        return list_obj

    def get_queryset(self):
        return ListChatMessage.objects.filter(list=self.get_list()).select_related(
            "author"
        )

    def perform_create(self, serializer):
        message = serializer.save(
            list=self.get_list(),
            author=self.request.user,
        )
        payload = ListChatMessageSerializer(message).data
        broadcast_chat_event(message.list_id, "message.created", payload)
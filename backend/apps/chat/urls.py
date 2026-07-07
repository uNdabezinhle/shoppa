from django.urls import path

from .views import ListMessageListView

urlpatterns = [
    path(
        "lists/<uuid:list_id>/messages",
        ListMessageListView.as_view(),
        name="list-messages",
    ),
]
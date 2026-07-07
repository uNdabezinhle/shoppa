from django.urls import path

from .views import ListDeliveryQuotesView

urlpatterns = [
    path(
        "lists/<uuid:list_id>/delivery-quotes",
        ListDeliveryQuotesView.as_view(),
        name="list-delivery-quotes",
    ),
]
from django.urls import path

from .views import PromotionListView, PromotionOptOutView

urlpatterns = [
    path("promotions", PromotionListView.as_view(), name="promotions-list"),
    path(
        "promotions/opt-out",
        PromotionOptOutView.as_view(),
        name="promotions-opt-out",
    ),
]

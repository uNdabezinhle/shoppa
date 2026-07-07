from django.urls import path

from .views import AdClickView, AdImpressionView, AdPlacementsView

urlpatterns = [
    path("ads/placements", AdPlacementsView.as_view(), name="ads-placements"),
    path("ads/impressions", AdImpressionView.as_view(), name="ads-impressions"),
    path("ads/clicks", AdClickView.as_view(), name="ads-clicks"),
]
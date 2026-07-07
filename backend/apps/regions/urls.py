from django.urls import path

from .views import RegionDetailView, RegionListView

urlpatterns = [
    path("regions", RegionListView.as_view(), name="regions-list"),
    path("regions/<str:code>", RegionDetailView.as_view(), name="regions-detail"),
]
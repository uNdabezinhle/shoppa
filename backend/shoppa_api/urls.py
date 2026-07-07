"""URL configuration for shoppa_api.

Mounted at the API root so that app-level urls only need to define paths
relative to /v1, matching the API Specification's versioning convention.
"""
from django.contrib import admin
from django.urls import include, path

urlpatterns = [
    path("admin/", admin.site.urls),
    path("v1/", include("apps.users.urls")),
    path("v1/", include("apps.lists.urls")),
    path("v1/", include("apps.price_intelligence.urls")),
    path("v1/", include("apps.promotions.urls")),
]

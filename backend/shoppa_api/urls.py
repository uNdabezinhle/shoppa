"""URL configuration for shoppa_api.

Mounted at the API root so that app-level urls only need to define paths
relative to /v1, matching the API Specification's versioning convention.
"""
from django.contrib import admin
from django.urls import include, path

from .platform import LaunchMetaView, health_check, readiness_check

urlpatterns = [
    path("v1/health/", health_check, name="health"),
    path("v1/health/ready/", readiness_check, name="health-ready"),
    path("v1/meta/launch", LaunchMetaView.as_view(), name="meta-launch"),
    path("admin/", admin.site.urls),
    path("v1/", include("apps.users.urls")),
    path("v1/", include("apps.lists.urls")),
    path("v1/", include("apps.price_intelligence.urls")),
    path("v1/", include("apps.promotions.urls")),
    path("v1/", include("apps.regions.urls")),
    path("v1/", include("apps.delivery.urls")),
    path("v1/", include("apps.chat.urls")),
    path("v1/", include("apps.notifications.urls")),
    path("v1/", include("apps.subscriptions.urls")),
    path("v1/", include("apps.admin_tools.urls")),
    path("v1/", include("apps.ads.urls")),
]

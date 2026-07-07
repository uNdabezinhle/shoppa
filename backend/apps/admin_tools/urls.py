from django.urls import path

from .views import (
    AdminOverviewView,
    ModerationActionView,
    ModerationQueueView,
    PartnerStoresView,
)

urlpatterns = [
    path("admin/overview", AdminOverviewView.as_view(), name="admin-overview"),
    path(
        "admin/moderation/quarantine",
        ModerationQueueView.as_view(),
        name="admin-moderation-queue",
    ),
    path(
        "admin/moderation/quarantine/<uuid:pk>",
        ModerationActionView.as_view(),
        name="admin-moderation-action",
    ),
    path(
        "admin/partners/stores",
        PartnerStoresView.as_view(),
        name="admin-partner-stores",
    ),
]
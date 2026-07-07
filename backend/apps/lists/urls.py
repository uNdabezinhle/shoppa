from django.urls import path

from .views import (
    CollaboratorDetailView,
    CollaboratorListView,
    ListActivityView,
    ListComparisonView,
    ListDetailView,
    ListDuplicateView,
    ListExportView,
    ListItemDetailView,
    ListItemListView,
    ListListView,
    ListScaleView,
    PublicListsView,
)

urlpatterns = [
    path("lists", ListListView.as_view(), name="lists-list"),
    path("lists/public", PublicListsView.as_view(), name="lists-public"),
    path("lists/<uuid:pk>", ListDetailView.as_view(), name="lists-detail"),
    path(
        "lists/<uuid:list_id>/items",
        ListItemListView.as_view(),
        name="list-items-list",
    ),
    path(
        "lists/<uuid:list_id>/items/<uuid:item_id>",
        ListItemDetailView.as_view(),
        name="list-items-detail",
    ),
    path(
        "lists/<uuid:list_id>/collaborators",
        CollaboratorListView.as_view(),
        name="list-collaborators-list",
    ),
    path(
        "lists/<uuid:list_id>/collaborators/<uuid:user_id>",
        CollaboratorDetailView.as_view(),
        name="list-collaborators-detail",
    ),
    path(
        "lists/<uuid:list_id>/activity",
        ListActivityView.as_view(),
        name="list-activity",
    ),
    path(
        "lists/<uuid:list_id>/comparison",
        ListComparisonView.as_view(),
        name="list-comparison",
    ),
    path(
        "lists/<uuid:pk>/duplicate",
        ListDuplicateView.as_view(),
        name="lists-duplicate",
    ),
    path(
        "lists/<uuid:pk>/scale",
        ListScaleView.as_view(),
        name="lists-scale",
    ),
    path(
        "lists/<uuid:pk>/export",
        ListExportView.as_view(),
        name="lists-export",
    ),
]

from django.urls import path

from .views import NotificationListView, NotificationReadView

urlpatterns = [
    path("notifications", NotificationListView.as_view(), name="notifications-list"),
    path(
        "notifications/<uuid:pk>/read",
        NotificationReadView.as_view(),
        name="notifications-read",
    ),
]
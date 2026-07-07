from django.urls import path

from .auth_views import LoginView, ThrottledTokenRefreshView
from .privacy_views import AccountDeleteView, DataExportView
from .views import MeView, PasswordResetView, RegisterView, UpgradeToProfessionalView

urlpatterns = [
    path("auth/register", RegisterView.as_view(), name="auth-register"),
    path("auth/login", LoginView.as_view(), name="auth-login"),
    path("auth/refresh", ThrottledTokenRefreshView.as_view(), name="auth-refresh"),
    path("auth/password-reset", PasswordResetView.as_view(), name="auth-password-reset"),
    path("users/me", MeView.as_view(), name="users-me"),
    path(
        "users/me/data-export",
        DataExportView.as_view(),
        name="users-data-export",
    ),
    path(
        "users/me/delete-account",
        AccountDeleteView.as_view(),
        name="users-delete-account",
    ),
    path(
        "users/me/upgrade",
        UpgradeToProfessionalView.as_view(),
        name="users-me-upgrade",
    ),
]

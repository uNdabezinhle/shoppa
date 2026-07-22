from django.urls import path

from .views import (
    AllergenProfileView,
    ProductByGtinView,
    ProductCorrectionView,
    ProductVerifyRefreshView,
    ProductVerifyView,
    ScanHistoryView,
)

urlpatterns = [
    path("products/verify", ProductVerifyView.as_view(), name="products-verify"),
    path(
        "products/verify/refresh",
        ProductVerifyRefreshView.as_view(),
        name="products-verify-refresh",
    ),
    path(
        "products/by-gtin/<str:gtin>",
        ProductByGtinView.as_view(),
        name="products-by-gtin",
    ),
    path(
        "products/corrections",
        ProductCorrectionView.as_view(),
        name="products-corrections",
    ),
    path(
        "users/me/allergen-profile",
        AllergenProfileView.as_view(),
        name="users-allergen-profile",
    ),
    path(
        "users/me/scan-history",
        ScanHistoryView.as_view(),
        name="users-scan-history",
    ),
]

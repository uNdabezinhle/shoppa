from django.urls import path

from .views import (
    PriceObservationCreateView,
    ProductPriceHistoryView,
    ProductSearchView,
    ProductStorePriceView,
)

urlpatterns = [
    path("products", ProductSearchView.as_view(), name="products-search"),
    path(
        "prices/observations",
        PriceObservationCreateView.as_view(),
        name="price-observations",
    ),
    path(
        "products/<uuid:product_id>/price-history",
        ProductPriceHistoryView.as_view(),
        name="product-price-history",
    ),
    path(
        "products/<uuid:product_id>/store-price",
        ProductStorePriceView.as_view(),
        name="product-store-price",
    ),
]

from django.urls import path

from .views import PriceObservationCreateView, ProductPriceHistoryView

urlpatterns = [
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
]

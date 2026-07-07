"""API Specification §6.4: POST /prices/observations uses product_id/
store_id keys (not the DRF-default "product"/"store"), matched here via
PrimaryKeyRelatedField(source=...).
"""
from rest_framework import serializers

from .models import CurrentPrice, PriceObservation, Product, Store


class ProductSerializer(serializers.ModelSerializer):
    class Meta:
        model = Product
        fields = ["id", "name", "region"]
        read_only_fields = fields


class ProductStorePriceSerializer(serializers.Serializer):
    store_id = serializers.UUIDField()
    price = serializers.IntegerField()
    confidence = serializers.CharField()


class PriceObservationSerializer(serializers.ModelSerializer):
    product_id = serializers.PrimaryKeyRelatedField(
        source="product", queryset=Product.objects.all()
    )
    store_id = serializers.PrimaryKeyRelatedField(
        source="store", queryset=Store.objects.all()
    )

    class Meta:
        model = PriceObservation
        fields = [
            "id", "product_id", "store_id", "price", "source",
            "observed_at", "is_quarantined", "created_at",
        ]
        read_only_fields = ["id", "source", "is_quarantined", "created_at"]


class PriceHistoryEntrySerializer(serializers.ModelSerializer):
    """GET /products/{id}/price-history: per API Specification, a
    time-series of observations for one product, one row per store per
    observation."""

    store_id = serializers.UUIDField(source="store.id", read_only=True)
    store_name = serializers.CharField(source="store.name", read_only=True)

    class Meta:
        model = PriceObservation
        fields = ["id", "store_id", "store_name", "price", "source", "observed_at"]

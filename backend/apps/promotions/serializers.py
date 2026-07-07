from rest_framework import serializers

from apps.price_intelligence.models import Store

from .models import Promotion, PromotionOptOut


class PromotionSerializer(serializers.ModelSerializer):
    store_id = serializers.UUIDField(source="store.id", read_only=True)
    store_name = serializers.CharField(source="store.name", read_only=True)
    product_id = serializers.UUIDField(source="product.id", read_only=True)
    product_name = serializers.CharField(source="product.name", read_only=True)

    class Meta:
        model = Promotion
        fields = [
            "id", "store_id", "store_name", "product_id", "product_name",
            "category", "title", "description", "starts_at", "ends_at",
        ]


class PromotionOptOutSerializer(serializers.ModelSerializer):
    """POST /v1/promotions/opt-out (API Specification §6.6). Accepts
    exactly one of store_id / category (FR-7.3) -- validated here so a
    bad request gets a 422 with a clear field error rather than tripping
    the model's CheckConstraint as a raw IntegrityError.
    """

    store_id = serializers.PrimaryKeyRelatedField(
        source="store", queryset=Store.objects.all(), required=False, allow_null=True
    )

    class Meta:
        model = PromotionOptOut
        fields = ["id", "store_id", "category", "created_at"]
        read_only_fields = ["id", "created_at"]

    def validate(self, attrs):
        store = attrs.get("store")
        category = attrs.get("category", "")
        if bool(store) == bool(category):
            raise serializers.ValidationError(
                "Provide exactly one of store_id or category."
            )
        return attrs

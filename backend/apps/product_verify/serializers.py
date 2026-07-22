from rest_framework import serializers

from .allergens import CANONICAL_ALLERGENS, normalize_allergen_list
from .models import ProductCorrection, UserAllergenProfile


class AllergenProfileSerializer(serializers.ModelSerializer):
    allergens = serializers.ListField(
        child=serializers.CharField(max_length=64),
        allow_empty=True,
    )
    consent = serializers.BooleanField(write_only=True, required=False)

    class Meta:
        model = UserAllergenProfile
        fields = ["allergens", "consent_at", "updated_at", "consent"]
        read_only_fields = ["consent_at", "updated_at"]

    def validate_allergens(self, value):
        return normalize_allergen_list(value)

    def validate(self, attrs):
        consent = attrs.pop("consent", None)
        if self.instance is None or consent is True:
            if consent is not True and self.instance is None:
                raise serializers.ValidationError(
                    {
                        "consent": (
                            "You must consent to storing allergen preferences "
                            "for food safety warnings (health data under POPIA)."
                        )
                    }
                )
        attrs["_consent"] = consent
        return attrs


class ProductCorrectionSerializer(serializers.ModelSerializer):
    class Meta:
        model = ProductCorrection
        fields = [
            "id",
            "gtin",
            "field",
            "suggested_value",
            "note",
            "status",
            "created_at",
        ]
        read_only_fields = ["id", "status", "created_at"]

    def validate_field(self, value):
        allowed = {
            "name",
            "brand",
            "ingredients_text",
            "allergens",
            "missing_product",
            "other",
        }
        if value not in allowed:
            raise serializers.ValidationError(
                f"field must be one of: {', '.join(sorted(allowed))}"
            )
        return value


class CanonicalAllergenSerializer(serializers.Serializer):
    code = serializers.CharField()
    label = serializers.CharField()


def canonical_allergen_list() -> list[dict[str, str]]:
    return [
        {"code": code, "label": label}
        for code, label in CANONICAL_ALLERGENS.items()
    ]

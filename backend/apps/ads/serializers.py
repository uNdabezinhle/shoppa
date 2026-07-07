from rest_framework import serializers

from .models import AdFormat, AdSurface


class AdImpressionSerializer(serializers.Serializer):
    placement_id = serializers.UUIDField()
    surface = serializers.ChoiceField(choices=AdSurface.choices)
    ad_format = serializers.ChoiceField(choices=AdFormat.choices)
    session_key = serializers.CharField(max_length=120, required=False, allow_blank=True)


class AdClickSerializer(serializers.Serializer):
    placement_id = serializers.UUIDField()
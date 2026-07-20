from rest_framework import serializers

from .models import Device, DevicePlatform


class DeviceSerializer(serializers.ModelSerializer):
    platform = serializers.ChoiceField(choices=DevicePlatform.choices)

    class Meta:
        model = Device
        fields = ["id", "token", "platform", "created_at", "updated_at"]
        read_only_fields = ["id", "created_at", "updated_at"]

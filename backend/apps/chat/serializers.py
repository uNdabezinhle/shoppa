from rest_framework import serializers

from .models import ListChatMessage


class ListChatMessageSerializer(serializers.ModelSerializer):
    author_id = serializers.UUIDField(source="author.id", read_only=True)
    author_email = serializers.EmailField(source="author.email", read_only=True)

    class Meta:
        model = ListChatMessage
        fields = ["id", "author_id", "author_email", "body", "created_at"]
        read_only_fields = ["id", "author_id", "author_email", "created_at"]

    def validate_body(self, value):
        trimmed = value.strip()
        if not trimmed:
            raise serializers.ValidationError("Message cannot be empty.")
        return trimmed
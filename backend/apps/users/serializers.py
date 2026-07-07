"""Serializers for registration and user representation.

Field names and the request/response shape follow the API Specification
§4 (Authentication) and §6.1 conventions (snake_case, UUID ids).
"""
from django.contrib.auth.password_validation import validate_password
from rest_framework import serializers

from .models import AccountType, User


class UserSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ["id", "email", "account_type", "region", "locale"]
        read_only_fields = fields


class UserUpdateSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ["locale"]
        extra_kwargs = {"locale": {"required": False}}


class PasswordResetRequestSerializer(serializers.Serializer):
    email = serializers.EmailField()


class RegisterSerializer(serializers.ModelSerializer):
    password = serializers.CharField(write_only=True, validators=[validate_password])
    account_type = serializers.ChoiceField(
        choices=AccountType.choices, default=AccountType.PERSONAL
    )
    region = serializers.CharField(max_length=8, default="ZA")

    class Meta:
        model = User
        fields = ["email", "password", "account_type", "region"]

    def validate_email(self, value):
        if User.objects.filter(email__iexact=value).exists():
            raise serializers.ValidationError("This email is already registered.")
        return value

    def create(self, validated_data):
        password = validated_data.pop("password")
        # `username` is required by AbstractUser; derive it from the email
        # since Shoppa authenticates by email, not username (FR-1.1).
        user = User(username=validated_data["email"], **validated_data)
        user.set_password(password)
        user.save()
        return user
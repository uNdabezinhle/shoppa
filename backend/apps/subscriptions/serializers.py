from rest_framework import serializers

from .models import SubscriptionPlan, UserSubscription


class SubscriptionPlanSerializer(serializers.ModelSerializer):
    class Meta:
        model = SubscriptionPlan
        fields = [
            "slug",
            "name",
            "price_monthly",
            "currency_code",
            "features",
            "max_owned_lists",
        ]


class UserSubscriptionSerializer(serializers.ModelSerializer):
    plan = SubscriptionPlanSerializer(read_only=True)
    feature_flags = serializers.SerializerMethodField()

    class Meta:
        model = UserSubscription
        fields = [
            "plan",
            "status",
            "feature_flags",
            "current_period_end",
            "created_at",
        ]

    def get_feature_flags(self, obj):
        if obj.status != UserSubscription.Status.ACTIVE:
            return []
        return list(obj.plan.features or [])
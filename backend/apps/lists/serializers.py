from rest_framework import serializers

from .models import ListActivity, ListCollaborator, ListItem, ShoppingList


class ListItemSerializer(serializers.ModelSerializer):
    # Set by offline clients replaying a queued mutation (SRS FR-4.2) so
    # the server can resolve conflicting edits deterministically -- see
    # ListItem.apply_field_updates(). Omitted on a normal online edit.
    client_updated_at = serializers.DateTimeField(write_only=True, required=False)
    # API Specification §6.2: PATCH .../items/{item_id} accepts store_id
    # alongside checked/paid_price on check-off, so the server can record
    # an implicit price observation (FR-5.4). Not a ListItem model field
    # -- it's consumed by the view, not persisted on the item itself.
    store_id = serializers.UUIDField(write_only=True, required=False, allow_null=True)
    # SRS FR-7.2: non-intrusive promotion flag on items linked to a
    # catalogue product with a live, non-opted-out promotion (SRS FR-7.1,
    # FR-7.3). Free-text items (no product_id) never flag.
    has_promotion = serializers.SerializerMethodField()

    class Meta:
        model = ListItem
        fields = [
            "id", "product_id", "name", "quantity", "unit", "note",
            "position", "checked", "paid_price", "created_at", "updated_at",
            "client_updated_at", "store_id", "has_promotion",
        ]
        read_only_fields = ["id", "created_at", "updated_at", "has_promotion"]

    def get_has_promotion(self, obj):
        request = self.context.get("request")
        user = getattr(request, "user", None)
        if user is None or not user.is_authenticated:
            # No request in context (e.g. a realtime broadcast payload
            # built outside a request/response cycle) -- fail closed
            # rather than flag a promotion to nobody in particular.
            return False
        from apps.promotions.services import has_active_promotion

        return has_active_promotion(user, obj.product_id)

    def create(self, validated_data):
        validated_data.pop("client_updated_at", None)
        validated_data.pop("store_id", None)
        return super().create(validated_data)

    def update(self, instance, validated_data):
        client_updated_at = validated_data.pop("client_updated_at", None)
        # Stashed for the view (ListItemDetailView.perform_update) to pick
        # up after saving -- see the implicit-observation note above.
        instance._requested_store_id = validated_data.pop("store_id", None)
        instance.apply_field_updates(validated_data, client_updated_at)
        instance.save()
        return instance


class ShoppingListSerializer(serializers.ModelSerializer):
    item_count = serializers.IntegerField(source="items.count", read_only=True)
    role = serializers.SerializerMethodField()

    class Meta:
        model = ShoppingList
        fields = [
            "id", "title", "category", "is_recurring", "recurrence",
            "is_public", "event_name", "event_date",
            "item_count", "role", "created_at", "updated_at",
        ]
        read_only_fields = ["id", "item_count", "role", "created_at", "updated_at"]

    def get_role(self, obj):
        request = self.context.get("request")
        if request is None:
            return None
        return obj.role_for(request.user)

    def validate(self, attrs):
        # SRS FR-8.2 (publish) / FR-8.3 (event attach): both are
        # Professional-only. A Personal account PATCHing these fields
        # gets a clear 422 rather than a silent no-op or a 403 on the
        # whole request (other fields in the same PATCH still apply).
        request = self.context.get("request")
        user = getattr(request, "user", None)
        professional_only_fields = {"is_public", "event_name", "event_date"}
        touched = professional_only_fields & set(attrs.keys())
        if touched and user is not None:
            from apps.users.models import AccountType

            if user.account_type != AccountType.PROFESSIONAL:
                raise serializers.ValidationError(
                    {
                        field: "This is a Professional feature."
                        for field in touched
                    }
                )
        return attrs


class ShoppingListDetailSerializer(ShoppingListSerializer):
    items = ListItemSerializer(many=True, read_only=True)

    class Meta(ShoppingListSerializer.Meta):
        fields = ShoppingListSerializer.Meta.fields + ["items"]


class ListCollaboratorSerializer(serializers.ModelSerializer):
    """Write side accepts an `email` (API Specification §6.3); read side
    also surfaces the resolved user's id/email so clients don't need a
    separate lookup.
    """

    email = serializers.EmailField(write_only=True)
    user_id = serializers.UUIDField(source="user.id", read_only=True)
    user_email = serializers.EmailField(source="user.email", read_only=True)

    class Meta:
        model = ListCollaborator
        fields = ["id", "email", "user_id", "user_email", "permission", "created_at"]
        read_only_fields = ["id", "user_id", "user_email", "created_at"]

    def validate(self, attrs):
        from apps.users.models import User

        list_obj = self.context["list"]
        email = attrs.get("email")
        try:
            user = User.objects.get(email__iexact=email)
        except User.DoesNotExist:
            raise serializers.ValidationError(
                {"email": "No user with this email exists."}
            )
        if user.id == list_obj.owner_id:
            raise serializers.ValidationError(
                {"email": "Cannot share a list with its owner."}
            )
        if ListCollaborator.objects.filter(list=list_obj, user=user).exists():
            raise serializers.ValidationError(
                {"email": "This user is already a collaborator."}
            )
        attrs["_user"] = user
        return attrs

    def create(self, validated_data):
        validated_data.pop("email", None)
        validated_data["user"] = validated_data.pop("_user")
        validated_data["list"] = self.context["list"]
        return ListCollaborator.objects.create(**validated_data)


class ListActivitySerializer(serializers.ModelSerializer):
    actor_email = serializers.SerializerMethodField()

    class Meta:
        model = ListActivity
        fields = ["id", "actor_email", "action", "detail", "created_at"]

    def get_actor_email(self, obj):
        return obj.actor.email if obj.actor_id else None

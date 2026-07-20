"""Shopping Lists (Solution Architecture §4: `lists` app).

Covers SRS FR-2.1 (categorized lists), FR-2.2 (item CRUD + reorder),
FR-2.3 (recurring lists), FR-3.1 (sharing at view/edit permission),
FR-3.3 (per-list activity feed). IDs are UUIDs per the API
Specification's resource-ID convention; item price fields are integer
minor units + the list owner's region implies currency (Architecture
§5, region-scoped money).
"""
import uuid

from django.conf import settings
from django.db import models
from django.utils import timezone
from django.utils.dateparse import parse_datetime


class ListCategory(models.TextChoices):
    GROCERIES = "groceries", "Groceries"
    CLOTHING = "clothing", "Clothing"
    WISHLIST = "wishlist", "Wishlist"
    EVENT = "event", "Event"
    INGREDIENTS = "ingredients", "Ingredients"
    CUSTOM = "custom", "Custom"


class CollaboratorPermission(models.TextChoices):
    VIEW = "view", "View"
    EDIT = "edit", "Edit"


class ShoppingList(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    owner = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="lists"
    )
    title = models.CharField(max_length=200)
    category = models.CharField(
        max_length=20, choices=ListCategory.choices, default=ListCategory.CUSTOM
    )
    is_recurring = models.BooleanField(default=False)
    recurrence = models.CharField(max_length=20, blank=True, default="")
    # SRS FR-8.2: Professional users can publish a list for others to
    # discover (GET /lists/public) and clone (POST /lists/{id}/duplicate,
    # which also accepts a public list from a non-owner). Personal
    # accounts never see this flag set -- enforced in
    # ShoppingListSerializer.validate(), not just at the DB layer.
    is_public = models.BooleanField(default=False)
    # SRS FR-8.3: Professional users can attach a list to a named event
    # with a date (e.g. a catering job or party) -- same Professional
    # gating as is_public, enforced in the same serializer.validate().
    event_name = models.CharField(max_length=200, blank=True, default="")
    event_date = models.DateField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return self.title

    def role_for(self, user):
        """Returns "owner", a CollaboratorPermission value, or None.

        None means the user has no access to this list at all — callers
        should treat that as a 404, not a 403, so we never leak whether a
        given list ID exists to someone uninvolved with it.
        """
        if user is None or not getattr(user, "is_authenticated", False):
            return None
        if self.owner_id == user.id:
            return "owner"
        collaborator = self.collaborators.filter(user=user).first()
        return collaborator.permission if collaborator else None


class ListItem(models.Model):
    #: Fields eligible for last-write-wins-by-field conflict resolution
    #: (SRS FR-3.2, FR-4.2; QA Test Plan TC-3.5, TC-4.5). Deliberately
    #: excludes id/list/created_at, which never change via PATCH.
    CONFLICT_FIELDS = (
        "product_id", "name", "quantity", "unit", "note",
        "position", "checked", "paid_price",
    )

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    list = models.ForeignKey(
        ShoppingList, on_delete=models.CASCADE, related_name="items"
    )
    # Optional catalogue link (price_intelligence.Product.id). Not a DB FK
    # so free-text items stay simple; serializer validates existence/region.
    product_id = models.UUIDField(null=True, blank=True)
    name = models.CharField(max_length=200)
    quantity = models.DecimalField(max_digits=10, decimal_places=2, default=1)
    unit = models.CharField(max_length=20, default="ea")
    note = models.CharField(max_length=280, blank=True, default="")
    position = models.PositiveIntegerField(default=0)
    checked = models.BooleanField(default=False)
    paid_price = models.PositiveIntegerField(null=True, blank=True)  # minor units
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    # Per-field "last write" timestamps (ISO strings), used to resolve
    # conflicting offline edits deterministically without a manual merge
    # step -- see apply_field_updates() below.
    field_synced_at = models.JSONField(default=dict, blank=True)

    class Meta:
        ordering = ["position", "created_at"]

    def __str__(self):
        return f"{self.name} x{self.quantity}"

    def apply_field_updates(self, data, client_updated_at=None):
        """Applies each field present in `data` using last-write-wins-by-
        field semantics: a field is only overwritten if this mutation is
        at least as new as whatever last touched that specific field.
        This is what lets two collaborators' offline queues, replayed in
        whatever order they happen to reconnect, converge on the same
        result (SRS FR-3.2/FR-4.2) instead of one wholesale clobbering
        the other.

        Without client_updated_at (an ordinary online edit, no offline
        queueing involved) every field is applied unconditionally and
        stamped with the current server time.

        Sets self._last_applied_fields to the set of field names that
        were actually written (fields that lost the conflict are left
        untouched) so callers can tell a genuine no-op apart from a real
        change -- e.g. to avoid logging a phantom activity entry or
        WebSocket broadcast for an edit that the server silently dropped.
        """
        effective_time = client_updated_at or timezone.now()
        synced = dict(self.field_synced_at or {})
        applied = set()
        for field in self.CONFLICT_FIELDS:
            if field not in data:
                continue
            last_raw = synced.get(field)
            last_dt = parse_datetime(last_raw) if last_raw else None
            if last_dt is not None and effective_time < last_dt:
                continue  # a newer edit already won this field
            setattr(self, field, data[field])
            synced[field] = effective_time.isoformat()
            applied.add(field)
        self.field_synced_at = synced
        self._last_applied_fields = applied
        return applied


class ListCollaborator(models.Model):
    """A user a list has been shared with (SRS FR-3.1).

    API Specification §6.3: POST/GET /lists/{id}/collaborators,
    DELETE /lists/{id}/collaborators/{user_id}.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    list = models.ForeignKey(
        ShoppingList, on_delete=models.CASCADE, related_name="collaborators"
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="shared_lists"
    )
    permission = models.CharField(
        max_length=10,
        choices=CollaboratorPermission.choices,
        default=CollaboratorPermission.VIEW,
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["list", "user"], name="unique_list_collaborator"
            )
        ]

    def __str__(self):
        return f"{self.user} on {self.list} ({self.permission})"


class ListInvite(models.Model):
    """Pending share for an email that is not yet a Shoppa user (FR-3.1).

    Converted to a ListCollaborator when that email registers. Cancelled
    via DELETE /lists/{id}/invites/{invite_id}.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    list = models.ForeignKey(
        ShoppingList, on_delete=models.CASCADE, related_name="invites"
    )
    email = models.EmailField(db_index=True)
    permission = models.CharField(
        max_length=10,
        choices=CollaboratorPermission.choices,
        default=CollaboratorPermission.VIEW,
    )
    invited_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="list_invites_sent",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        constraints = [
            models.UniqueConstraint(
                fields=["list", "email"], name="unique_list_invite_email"
            )
        ]

    def __str__(self):
        return f"invite {self.email} on {self.list} ({self.permission})"


class ListActivityAction(models.TextChoices):
    ITEM_ADDED = "item_added", "Item added"
    ITEM_UPDATED = "item_updated", "Item updated"
    ITEM_CHECKED = "item_checked", "Item checked"
    ITEM_REMOVED = "item_removed", "Item removed"
    COLLABORATOR_JOINED = "collaborator_joined", "Collaborator joined"
    COLLABORATOR_REMOVED = "collaborator_removed", "Collaborator removed"
    LIST_SCALED = "list_scaled", "List scaled"
    LIST_CREATED = "list_created", "List created"
    LIST_UPDATED = "list_updated", "List updated"
    LIST_PUBLISHED = "list_published", "List published"
    LIST_UNPUBLISHED = "list_unpublished", "List unpublished"


class ListActivity(models.Model):
    """Per-list activity feed (SRS FR-3.3, API Specification §6.3
    GET /lists/{id}/activity). Recorded on every item mutation and every
    collaborator add/remove.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    list = models.ForeignKey(
        ShoppingList, on_delete=models.CASCADE, related_name="activity"
    )
    actor = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        related_name="+",
    )
    action = models.CharField(max_length=30, choices=ListActivityAction.choices)
    detail = models.CharField(max_length=280, blank=True, default="")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]
        verbose_name_plural = "list activity"

    def __str__(self):
        return f"{self.action} on {self.list} by {self.actor}"

"""Shopping list & item views (SRS §3.2, §3.3).

FR-2.1: create lists with a category. FR-2.3: recurring flag.
FR-2.2: add/edit/remove/reorder items with quantity, unit, and notes —
reordering is done by PATCHing an item's `position`.
FR-3.1: share a list at view or edit permission. View collaborators can
read the list and its items but never mutate them; edit collaborators
can mutate items but not the list's own title/category/deletion, and
never manage collaborators — only the owner can do that.
FR-3.3: every item mutation and collaborator add/remove is recorded to
a per-list activity feed.
"""
import csv
import io
from decimal import Decimal, InvalidOperation

from django.http import Http404, HttpResponse
from django.shortcuts import get_object_or_404
from django.db.models import Q
from rest_framework import generics, permissions
from rest_framework.pagination import CursorPagination
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.price_intelligence.models import PriceSource, Product, Store
from apps.price_intelligence.services import compare_stores_for_list, record_observation
from apps.users.models import AccountType

from .models import (
    CollaboratorPermission,
    ListActivity,
    ListActivityAction,
    ListCollaborator,
    ListItem,
    ShoppingList,
)
from .realtime import broadcast_list_event
from .serializers import (
    ListActivitySerializer,
    ListCollaboratorSerializer,
    ListItemSerializer,
    ShoppingListDetailSerializer,
    ShoppingListSerializer,
)


def _accessible_lists(user):
    return ShoppingList.objects.filter(
        Q(owner=user) | Q(collaborators__user=user)
    ).distinct()


class ListCursorPagination(CursorPagination):
    """CursorPagination needs a stable ordering field; ShoppingList orders
    by -created_at (Meta.ordering), so pagination follows the same field.
    """
    ordering = "-created_at"
    page_size = 20


class ListListView(generics.ListCreateAPIView):
    """Index includes lists the user owns *and* lists shared with them,
    so shared lists surface in the Mall screen alongside the user's own.
    """

    serializer_class = ShoppingListSerializer
    permission_classes = [permissions.IsAuthenticated]
    pagination_class = ListCursorPagination

    def get_queryset(self):
        return (
            _accessible_lists(self.request.user)
            .select_related("owner")
            .prefetch_related("collaborators__user")
        )

    def create(self, request, *args, **kwargs):
        from apps.subscriptions.services import assert_can_create_list

        assert_can_create_list(request.user)
        return super().create(request, *args, **kwargs)

    def perform_create(self, serializer):
        serializer.save(owner=self.request.user)


class PublicListsView(generics.ListAPIView):
    """GET /v1/lists/public (SRS FR-8.2): published lists from any user,
    for discovery/cloning. Deliberately excludes the caller's own lists
    -- there's no point discovering something you already own.
    """

    serializer_class = ShoppingListSerializer
    permission_classes = [permissions.IsAuthenticated]
    pagination_class = ListCursorPagination

    def get_queryset(self):
        return ShoppingList.objects.filter(is_public=True).exclude(
            owner=self.request.user
        )


class ListDetailPermission(permissions.BasePermission):
    """SAFE methods are open to any role (owner/view/edit); mutating the
    list itself (title/category/recurrence) or deleting it is owner-only.
    """

    def has_object_permission(self, request, view, obj):
        role = obj.role_for(request.user)
        if role is None:
            return False
        if request.method in permissions.SAFE_METHODS:
            return True
        return role == "owner"


class ListDetailView(generics.RetrieveUpdateDestroyAPIView):
    serializer_class = ShoppingListDetailSerializer
    permission_classes = [permissions.IsAuthenticated, ListDetailPermission]

    def get_queryset(self):
        return _accessible_lists(self.request.user)


class ListDuplicateView(APIView):
    """POST /v1/lists/{id}/duplicate (API Specification §6.1). Any role
    with access to the source list can duplicate it; a *published*
    list (FR-8.2, is_public) can also be duplicated -- "cloned" -- by
    anyone, not just people already on it. The duplicate is a fresh,
    unchecked, price-less copy owned by the caller -- it's a new list,
    not a shared reference to the original.
    """

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        from apps.subscriptions.services import assert_can_create_list

        source = get_object_or_404(ShoppingList, pk=pk)
        if source.role_for(request.user) is None and not source.is_public:
            raise Http404

        # Same free-tier owned-list cap as POST /lists (duplicate is a create).
        assert_can_create_list(request.user)

        clone = ShoppingList.objects.create(
            owner=request.user,
            title=source.title,
            category=source.category,
            is_recurring=source.is_recurring,
            recurrence=source.recurrence,
        )
        ListItem.objects.bulk_create(
            [
                ListItem(
                    list=clone,
                    product_id=item.product_id,
                    name=item.name,
                    quantity=item.quantity,
                    unit=item.unit,
                    note=item.note,
                    position=item.position,
                    # Deliberately not copied: a duplicate starts fresh --
                    # checked/paid_price belong to a specific shopping
                    # trip, not the list template.
                )
                for item in source.items.all()
            ]
        )
        return Response(
            ShoppingListDetailSerializer(clone, context={"request": request}).data,
            status=201,
        )


class ListScaleView(APIView):
    """POST /v1/lists/{id}/scale (SRS FR-8.1, API Specification §6.1).
    Professional-only, owner-only. Body: exactly one of {"factor": N} or
    {"guests": N} -- both scale every item's quantity by N; "guests" is
    just the domain-friendly name for the same operation (the list's
    current quantities are treated as designed for one guest/unit).
    """

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, pk):
        list_obj = get_object_or_404(ShoppingList, pk=pk)
        if list_obj.role_for(request.user) != "owner":
            raise Http404
        if request.user.account_type != AccountType.PROFESSIONAL:
            self.permission_denied(
                request, message="Scaling a list is a Professional feature."
            )

        factor = request.data.get("factor")
        guests = request.data.get("guests")
        if (factor is None) == (guests is None):
            return Response(
                {
                    "error": {
                        "code": "validation_error",
                        "message": "Provide exactly one of factor or guests.",
                    }
                },
                status=422,
            )
        try:
            multiplier = Decimal(str(factor if factor is not None else guests))
        except (InvalidOperation, TypeError, ValueError):
            return Response(
                {
                    "error": {
                        "code": "validation_error",
                        "message": "factor/guests must be a number.",
                    }
                },
                status=422,
            )
        if multiplier <= 0:
            return Response(
                {
                    "error": {
                        "code": "validation_error",
                        "message": "factor/guests must be greater than zero.",
                    }
                },
                status=422,
            )

        items = list(list_obj.items.all())
        for item in items:
            item.quantity = item.quantity * multiplier
        ListItem.objects.bulk_update(items, ["quantity"])

        ListActivity.objects.create(
            list=list_obj,
            actor=request.user,
            action=ListActivityAction.LIST_SCALED,
            detail=f"scaled by {multiplier.normalize()}",
        )
        broadcast_list_event(
            list_obj.id,
            "list.scaled",
            {"items": ListItemSerializer(items, many=True).data},
        )
        return Response(
            ShoppingListDetailSerializer(list_obj, context={"request": request}).data
        )


class ListExportView(APIView):
    """GET /v1/lists/{id}/export?format=csv|pdf (SRS FR-8.4). Open to any
    role with access to the list -- unlike scale/publish/event, export
    isn't marked Professional-only in the SRS.
    """

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, pk):
        list_obj = get_object_or_404(ShoppingList, pk=pk)
        if list_obj.role_for(request.user) is None:
            raise Http404

        # Deliberately "type", not "format": DRF's content negotiation
        # reserves the "format" query parameter (URL_FORMAT_OVERRIDE) to
        # pick a *DRF renderer* by its .format attribute -- since this
        # view returns raw HttpResponse objects and never runs through
        # DRF's renderer pipeline on the success path, a query param
        # named "format" that doesn't match a registered renderer would
        # make DRF's own content negotiation raise Http404 before this
        # method ever runs.
        export_type = request.query_params.get("type", "csv").lower()
        items = list(list_obj.items.all())
        if export_type == "csv":
            return self._csv_response(list_obj, items)
        if export_type == "pdf":
            return self._pdf_response(list_obj, items)
        return Response(
            {
                "error": {
                    "code": "validation_error",
                    "message": "type must be 'csv' or 'pdf'.",
                }
            },
            status=422,
        )

    def _csv_response(self, list_obj, items):
        buffer = io.StringIO()
        writer = csv.writer(buffer)
        writer.writerow(["Name", "Quantity", "Unit", "Note", "Checked", "Paid Price"])
        for item in items:
            writer.writerow(
                [
                    item.name,
                    item.quantity,
                    item.unit,
                    item.note,
                    "yes" if item.checked else "no",
                    "" if item.paid_price is None else f"{item.paid_price / 100:.2f}",
                ]
            )
        response = HttpResponse(buffer.getvalue(), content_type="text/csv")
        response["Content-Disposition"] = (
            f'attachment; filename="{list_obj.title}.csv"'
        )
        return response

    def _pdf_response(self, list_obj, items):
        # Imported lazily so a CSV-only deployment (or a test run that
        # never hits this branch) doesn't pay reportlab's import cost.
        from reportlab.lib import colors
        from reportlab.lib.pagesizes import A4
        from reportlab.platypus import SimpleDocTemplate, Table, TableStyle, Paragraph
        from reportlab.lib.styles import getSampleStyleSheet

        buffer = io.BytesIO()
        doc = SimpleDocTemplate(buffer, pagesize=A4)
        styles = getSampleStyleSheet()

        rows = [["Name", "Qty", "Unit", "Note", "Checked", "Paid"]]
        for item in items:
            rows.append(
                [
                    item.name,
                    str(item.quantity),
                    item.unit,
                    item.note,
                    "✓" if item.checked else "",
                    "" if item.paid_price is None else f"{item.paid_price / 100:.2f}",
                ]
            )
        table = Table(rows, repeatRows=1)
        table.setStyle(
            TableStyle(
                [
                    ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#12161F")),
                    ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                    ("FONTNAME", (0, 0), (-1, 0), "Helvetica-Bold"),
                    ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
                    ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ]
            )
        )
        doc.build([Paragraph(list_obj.title, styles["Title"]), table])

        response = HttpResponse(buffer.getvalue(), content_type="application/pdf")
        response["Content-Disposition"] = (
            f'attachment; filename="{list_obj.title}.pdf"'
        )
        return response


class SharedListMixin:
    """Resolves the parent list from the URL for nested (item/collaborator/
    activity) endpoints. 404s — not 403s — for users with no role on the
    list at all, so item endpoints never leak whether a list exists.
    """

    list_role = None

    def get_list(self):
        list_obj = get_object_or_404(ShoppingList, pk=self.kwargs["list_id"])
        role = list_obj.role_for(self.request.user)
        if role is None:
            raise Http404
        self.list_role = role
        return list_obj

    def check_write_access(self):
        if self.list_role not in ("owner", "edit"):
            self.permission_denied(
                self.request,
                message="View-only collaborators cannot modify this list.",
            )


class ItemCursorPagination(CursorPagination):
    """Items order by position (then created_at) — see ListItem.Meta.ordering."""

    ordering = ("position", "created_at")
    page_size = 50


class ListItemListView(SharedListMixin, generics.ListCreateAPIView):
    serializer_class = ListItemSerializer
    permission_classes = [permissions.IsAuthenticated]
    pagination_class = ItemCursorPagination

    def get_queryset(self):
        return ListItem.objects.filter(list=self.get_list())

    def perform_create(self, serializer):
        list_obj = self.get_list()
        self.check_write_access()
        item = serializer.save(list=list_obj)
        ListActivity.objects.create(
            list=list_obj,
            actor=self.request.user,
            action=ListActivityAction.ITEM_ADDED,
            detail=item.name,
        )
        broadcast_list_event(
            list_obj.id, "item.added", ListItemSerializer(item).data
        )


class ListItemDetailView(SharedListMixin, generics.RetrieveUpdateDestroyAPIView):
    serializer_class = ListItemSerializer
    permission_classes = [permissions.IsAuthenticated]
    lookup_url_kwarg = "item_id"

    def get_queryset(self):
        return ListItem.objects.filter(list=self.get_list())

    def perform_update(self, serializer):
        self.check_write_access()
        item = serializer.save()
        applied_fields = getattr(item, "_last_applied_fields", None)
        if applied_fields is None:
            # No conflict-resolution path was involved (e.g. this instance
            # was saved some other way) -- fall back to "whatever was sent".
            applied_fields = set(self.request.data.keys())
        if not applied_fields:
            # Every field in this request lost to a newer edit (SRS FR-4.2,
            # QA Test Plan TC-4.5) -- nothing actually changed, so there's
            # nothing to log or broadcast. The response still reflects the
            # server's current (winning) state.
            return
        is_check = "checked" in applied_fields
        self._maybe_record_price_observation(item)
        action = (
            ListActivityAction.ITEM_CHECKED
            if is_check
            else ListActivityAction.ITEM_UPDATED
        )
        ListActivity.objects.create(
            list=item.list, actor=self.request.user, action=action, detail=item.name
        )
        event = "item.checked" if is_check else "item.updated"
        broadcast_list_event(item.list_id, event, ListItemSerializer(item).data)

    def _maybe_record_price_observation(self, item):
        """FR-5.4: checking off an item with a paid price and a store
        implicitly submits a crowd-sourced price observation, sharing the
        exact same ingestion/reconciliation path (and outlier quarantine,
        and price-drop alerting) as an explicit POST to
        /prices/observations. Silently does nothing if the item isn't
        checked, has no paid_price, isn't linked to a catalogue product,
        or no store_id was supplied -- this is a bonus side-effect of
        check-off, never a reason to fail the request.
        """
        store_id = getattr(item, "_requested_store_id", None)
        if not (item.checked and item.paid_price is not None and item.product_id and store_id):
            return
        product = Product.objects.filter(id=item.product_id).first()
        store = Store.objects.filter(id=store_id).first()
        if not (product and store):
            return
        record_observation(
            product=product,
            store=store,
            price=item.paid_price,
            source=PriceSource.CROWD,
            submitted_by=self.request.user,
        )

    def perform_destroy(self, instance):
        self.check_write_access()
        list_id = instance.list_id
        item_id = str(instance.id)
        ListActivity.objects.create(
            list=instance.list,
            actor=self.request.user,
            action=ListActivityAction.ITEM_REMOVED,
            detail=instance.name,
        )
        instance.delete()
        # Not in the API Specification's illustrative event list, but a
        # natural extension: without it, a removed item would linger on
        # other collaborators' screens until their next manual refresh.
        broadcast_list_event(list_id, "item.removed", {"id": item_id})


class CollaboratorListView(SharedListMixin, generics.ListCreateAPIView):
    """GET is open to the owner and any existing collaborator (so anyone
    on the list can see who else is on it). POST (inviting someone new)
    is owner-only regardless of the caller's role.
    """

    serializer_class = ListCollaboratorSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return ListCollaborator.objects.filter(list=self.get_list())

    def get_serializer_context(self):
        context = super().get_serializer_context()
        context["list"] = self.get_list()
        return context

    def perform_create(self, serializer):
        list_obj = self.get_list()
        if self.list_role != "owner":
            self.permission_denied(
                self.request, message="Only the list owner can add collaborators."
            )
        collaborator = serializer.save()
        ListActivity.objects.create(
            list=list_obj,
            actor=self.request.user,
            action=ListActivityAction.COLLABORATOR_JOINED,
            detail=f"{collaborator.user.email} added as {collaborator.permission}",
        )
        broadcast_list_event(
            list_obj.id,
            "collaborator.joined",
            ListCollaboratorSerializer(collaborator).data,
        )


class CollaboratorDetailView(APIView):
    """PATCH permission (owner-only) or DELETE collaborator.

    DELETE: list owner may remove any collaborator; a collaborator may
    remove only themselves (self-leave). Everyone else gets 404 so we
    never leak list existence (same convention as SharedListMixin).
    """

    permission_classes = [permissions.IsAuthenticated]

    def _resolve(self, request, list_id, user_id):
        list_obj = get_object_or_404(ShoppingList, pk=list_id)
        role = list_obj.role_for(request.user)
        if role is None:
            raise Http404
        collaborator = get_object_or_404(
            ListCollaborator, list=list_obj, user_id=user_id
        )
        return list_obj, role, collaborator

    def patch(self, request, list_id, user_id):
        list_obj, role, collaborator = self._resolve(request, list_id, user_id)
        if role != "owner":
            raise Http404
        permission = request.data.get("permission")
        if permission not in (
            CollaboratorPermission.VIEW,
            CollaboratorPermission.EDIT,
        ):
            return Response(
                {
                    "error": {
                        "code": "validation_error",
                        "message": "permission must be 'view' or 'edit'.",
                    }
                },
                status=422,
            )
        if collaborator.permission != permission:
            collaborator.permission = permission
            collaborator.save(update_fields=["permission"])
            ListActivity.objects.create(
                list=list_obj,
                actor=request.user,
                action=ListActivityAction.COLLABORATOR_JOINED,
                detail=(
                    f"{collaborator.user.email} permission set to {permission}"
                ),
            )
            broadcast_list_event(
                list_obj.id,
                "collaborator.updated",
                ListCollaboratorSerializer(collaborator).data,
            )
        return Response(ListCollaboratorSerializer(collaborator).data)

    def delete(self, request, list_id, user_id):
        list_obj, role, collaborator = self._resolve(request, list_id, user_id)
        is_owner = role == "owner"
        is_self = str(request.user.id) == str(user_id)
        if not is_owner and not is_self:
            raise Http404
        # Owners are not collaborator rows; self-leave is for collaborators only.
        if is_owner and is_self:
            raise Http404

        email = collaborator.user.email
        removed_user_id = str(collaborator.user_id)
        detail = (
            f"{email} left the list"
            if is_self and not is_owner
            else f"{email} removed"
        )
        ListActivity.objects.create(
            list=list_obj,
            actor=request.user,
            action=ListActivityAction.COLLABORATOR_REMOVED,
            detail=detail,
        )
        collaborator.delete()
        broadcast_list_event(
            list_obj.id,
            "collaborator.removed",
            {"user_id": removed_user_id},
        )
        return Response(status=204)


class ActivityCursorPagination(CursorPagination):
    ordering = "-created_at"
    page_size = 50


class ListActivityView(SharedListMixin, generics.ListAPIView):
    serializer_class = ListActivitySerializer
    permission_classes = [permissions.IsAuthenticated]
    pagination_class = ActivityCursorPagination

    def get_queryset(self):
        return ListActivity.objects.filter(list=self.get_list())


class ListComparisonView(SharedListMixin, APIView):
    """GET /v1/lists/{id}/comparison (FR-5.3, API Specification §6.4).
    Read-only, so any role with access to the list (owner, view, or edit
    collaborator) can see it -- comparison shopping isn't a mutation.
    """

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, list_id):
        list_obj = self.get_list()
        return Response(compare_stores_for_list(list_obj))

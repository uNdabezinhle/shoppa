"""Shopping list tests.

Traces to the QA Test Plan §5.2: TC-2.1 (this file). Item CRUD tests
(TC-2.2) land alongside the item endpoints.
"""
from datetime import timedelta
from unittest.mock import patch

from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from apps.users.models import User

from .models import ListCategory, ListItem, ShoppingList


class ShoppingListTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username="shopper@example.com",
            email="shopper@example.com",
            password="a-strong-passw0rd!",
        )
        self.other_user = User.objects.create_user(
            username="other@example.com",
            email="other@example.com",
            password="a-strong-passw0rd!",
        )
        self.client.force_authenticate(self.user)
        self.url = reverse("lists-list")

    def test_create_lists_in_each_category_persists_category(self):
        """TC-2.1: create lists in each category; category persists."""
        for category, _ in ListCategory.choices:
            response = self.client.post(
                self.url,
                {"title": f"My {category} list", "category": category},
                format="json",
            )
            self.assertEqual(response.status_code, status.HTTP_201_CREATED)
            self.assertEqual(response.data["category"], category)

        list_ids = ShoppingList.objects.filter(owner=self.user).values_list(
            "category", flat=True
        )
        self.assertEqual(set(list_ids), {c for c, _ in ListCategory.choices})

    def test_list_defaults_to_custom_category_and_non_recurring(self):
        response = self.client.post(
            self.url, {"title": "Untitled"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["category"], "custom")
        self.assertFalse(response.data["is_recurring"])

    def test_user_only_sees_their_own_lists(self):
        ShoppingList.objects.create(
            owner=self.user, title="Mine", category=ListCategory.GROCERIES
        )
        ShoppingList.objects.create(
            owner=self.other_user, title="Not mine", category=ListCategory.GROCERIES
        )
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        titles = [item["title"] for item in response.data["results"]]
        self.assertEqual(titles, ["Mine"])

    def test_recurring_list_stores_recurrence(self):
        response = self.client.post(
            self.url,
            {
                "title": "Monthly Groceries",
                "category": "groceries",
                "is_recurring": True,
                "recurrence": "monthly",
            },
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertTrue(response.data["is_recurring"])
        self.assertEqual(response.data["recurrence"], "monthly")

    def test_unauthenticated_request_is_rejected(self):
        self.client.force_authenticate(None)
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_user_cannot_access_another_users_list_detail(self):
        other_list = ShoppingList.objects.create(
            owner=self.other_user, title="Not mine", category=ListCategory.GROCERIES
        )
        response = self.client.get(
            reverse("lists-detail", kwargs={"pk": other_list.id})
        )
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)


class ListItemTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            username="shopper@example.com",
            email="shopper@example.com",
            password="a-strong-passw0rd!",
        )
        self.other_user = User.objects.create_user(
            username="other@example.com",
            email="other@example.com",
            password="a-strong-passw0rd!",
        )
        self.client.force_authenticate(self.user)
        self.list = ShoppingList.objects.create(
            owner=self.user, title="Monthly Groceries", category=ListCategory.GROCERIES
        )
        self.items_url = reverse("list-items-list", kwargs={"list_id": self.list.id})

    def _item_url(self, item_id):
        return reverse(
            "list-items-detail", kwargs={"list_id": self.list.id, "item_id": item_id}
        )

    def test_add_item_with_quantity_unit_and_note(self):
        """TC-2.2: add items with quantity, unit, notes."""
        response = self.client.post(
            self.items_url,
            {
                "name": "Full cream milk 2L",
                "quantity": 2,
                "unit": "ea",
                "note": "any brand on promo",
            },
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data["name"], "Full cream milk 2L")
        self.assertEqual(response.data["note"], "any brand on promo")

    def test_edit_item_quantity(self):
        """TC-2.2: edit items."""
        item = ListItem.objects.create(list=self.list, name="Eggs", quantity=1)
        response = self.client.patch(
            self._item_url(item.id), {"quantity": 3}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        item.refresh_from_db()
        self.assertEqual(item.quantity, 3)

    def test_check_off_item_records_paid_price(self):
        """Checking off an item stores the actual price (feeds FR-4.3 later)."""
        item = ListItem.objects.create(list=self.list, name="Bread", quantity=1)
        response = self.client.patch(
            self._item_url(item.id),
            {"checked": True, "paid_price": 1799},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data["checked"])
        self.assertEqual(response.data["paid_price"], 1799)

    def test_remove_item(self):
        """TC-2.2: remove items."""
        item = ListItem.objects.create(list=self.list, name="Rice", quantity=1)
        response = self.client.delete(self._item_url(item.id))
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(ListItem.objects.filter(id=item.id).exists())

    def test_reorder_items_via_position(self):
        """TC-2.2: reorder items."""
        first = ListItem.objects.create(list=self.list, name="A", position=0)
        second = ListItem.objects.create(list=self.list, name="B", position=1)

        self.client.patch(self._item_url(first.id), {"position": 1}, format="json")
        self.client.patch(self._item_url(second.id), {"position": 0}, format="json")

        response = self.client.get(self.items_url)
        ordered_names = [item["name"] for item in response.data["results"]]
        self.assertEqual(ordered_names, ["B", "A"])

    def test_cannot_add_items_to_another_users_list(self):
        other_list = ShoppingList.objects.create(
            owner=self.other_user, title="Not mine", category=ListCategory.GROCERIES
        )
        url = reverse("list-items-list", kwargs={"list_id": other_list.id})
        response = self.client.post(url, {"name": "Sneaky item"}, format="json")
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)


class CollaborationTests(APITestCase):
    """Traces to the QA Test Plan §5.3 (Collaboration): TC-3.1 (share at
    view/edit permission) and TC-3.3 (activity feed).
    """

    def setUp(self):
        self.owner = User.objects.create_user(
            username="owner@example.com",
            email="owner@example.com",
            password="a-strong-passw0rd!",
        )
        self.friend = User.objects.create_user(
            username="friend@example.com",
            email="friend@example.com",
            password="a-strong-passw0rd!",
        )
        self.stranger = User.objects.create_user(
            username="stranger@example.com",
            email="stranger@example.com",
            password="a-strong-passw0rd!",
        )
        self.list = ShoppingList.objects.create(
            owner=self.owner, title="Braai", category=ListCategory.GROCERIES
        )
        self.collaborators_url = reverse(
            "list-collaborators-list", kwargs={"list_id": self.list.id}
        )
        self.items_url = reverse("list-items-list", kwargs={"list_id": self.list.id})
        self.activity_url = reverse("list-activity", kwargs={"list_id": self.list.id})
        self.list_detail_url = reverse("lists-detail", kwargs={"pk": self.list.id})

    def _share(self, permission="view"):
        self.client.force_authenticate(self.owner)
        response = self.client.post(
            self.collaborators_url,
            {"email": self.friend.email, "permission": permission},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        return response

    def test_share_list_at_view_permission_collaborator_cannot_edit(self):
        """TC-3.1: share a list at view permission; collaborator cannot edit."""
        self._share(permission="view")

        self.client.force_authenticate(self.friend)
        list_response = self.client.get(self.list_detail_url)
        self.assertEqual(list_response.status_code, status.HTTP_200_OK)
        self.assertEqual(list_response.data["role"], "view")

        add_response = self.client.post(
            self.items_url, {"name": "Boerewors"}, format="json"
        )
        self.assertEqual(add_response.status_code, status.HTTP_403_FORBIDDEN)

    def test_share_list_at_edit_permission_collaborator_can_edit_items(self):
        self._share(permission="edit")

        self.client.force_authenticate(self.friend)
        add_response = self.client.post(
            self.items_url, {"name": "Boerewors"}, format="json"
        )
        self.assertEqual(add_response.status_code, status.HTTP_201_CREATED)

    def test_edit_collaborator_cannot_change_list_itself(self):
        """Edit permission covers items, not the list's own title/deletion —
        that stays owner-only."""
        self._share(permission="edit")

        self.client.force_authenticate(self.friend)
        response = self.client.patch(
            self.list_detail_url, {"title": "Renamed"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_shared_list_appears_in_collaborators_index(self):
        self._share(permission="view")

        self.client.force_authenticate(self.friend)
        response = self.client.get(reverse("lists-list"))
        ids = [item["id"] for item in response.data["results"]]
        self.assertIn(str(self.list.id), ids)

    def test_stranger_gets_404_not_403_on_shared_endpoints(self):
        self.client.force_authenticate(self.stranger)
        self.assertEqual(
            self.client.get(self.list_detail_url).status_code,
            status.HTTP_404_NOT_FOUND,
        )
        self.assertEqual(
            self.client.get(self.items_url).status_code, status.HTTP_404_NOT_FOUND
        )
        self.assertEqual(
            self.client.get(self.activity_url).status_code,
            status.HTTP_404_NOT_FOUND,
        )

    def test_only_owner_can_add_collaborators(self):
        self._share(permission="edit")

        self.client.force_authenticate(self.friend)
        response = self.client.post(
            self.collaborators_url,
            {"email": self.stranger.email, "permission": "view"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_cannot_share_with_owner_or_twice(self):
        self.client.force_authenticate(self.owner)
        own_email_response = self.client.post(
            self.collaborators_url,
            {"email": self.owner.email, "permission": "view"},
            format="json",
        )
        self.assertEqual(own_email_response.status_code, status.HTTP_400_BAD_REQUEST)

        self._share(permission="view")
        dup_response = self.client.post(
            self.collaborators_url,
            {"email": self.friend.email, "permission": "edit"},
            format="json",
        )
        self.assertEqual(dup_response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_share_with_unknown_email_is_rejected(self):
        self.client.force_authenticate(self.owner)
        response = self.client.post(
            self.collaborators_url,
            {"email": "nobody@example.com", "permission": "view"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_owner_can_remove_collaborator_and_access_is_revoked(self):
        self._share(permission="edit")

        self.client.force_authenticate(self.owner)
        detail_url = reverse(
            "list-collaborators-detail",
            kwargs={"list_id": self.list.id, "user_id": self.friend.id},
        )
        response = self.client.delete(detail_url)
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)

        self.client.force_authenticate(self.friend)
        self.assertEqual(
            self.client.get(self.list_detail_url).status_code,
            status.HTTP_404_NOT_FOUND,
        )

    def test_activity_feed_records_item_add_with_author_and_timestamp(self):
        """TC-3.3: activity feed records add/remove with author and timestamp."""
        self._share(permission="edit")

        self.client.force_authenticate(self.friend)
        item_response = self.client.post(
            self.items_url, {"name": "Boerewors"}, format="json"
        )
        item_id = item_response.data["id"]
        item_detail_url = reverse(
            "list-items-detail",
            kwargs={"list_id": self.list.id, "item_id": item_id},
        )
        self.client.delete(item_detail_url)

        self.client.force_authenticate(self.owner)
        response = self.client.get(self.activity_url)
        entries = response.data["results"]

        added = next(e for e in entries if e["action"] == "item_added")
        self.assertEqual(added["actor_email"], self.friend.email)
        self.assertIsNotNone(added["created_at"])

        removed = next(e for e in entries if e["action"] == "item_removed")
        self.assertEqual(removed["actor_email"], self.friend.email)

        joined = next(e for e in entries if e["action"] == "collaborator_joined")
        self.assertEqual(joined["actor_email"], self.owner.email)


class RealtimeBroadcastTests(APITestCase):
    """Traces to SRS FR-3.2 / QA Test Plan TC-3.2: verifies each REST
    mutation fans out the correct WebSocket event (API Specification §9,
    ws /lists/{id}) with the correct payload. The transport itself
    (ListConsumer) is covered by tests_realtime.py; this only checks the
    REST-side wiring, mocked so it doesn't need a running channel layer.
    """

    def setUp(self):
        self.owner = User.objects.create_user(
            username="owner2@example.com",
            email="owner2@example.com",
            password="a-strong-passw0rd!",
        )
        self.list = ShoppingList.objects.create(
            owner=self.owner, title="Weekend", category=ListCategory.GROCERIES
        )
        self.client.force_authenticate(self.owner)
        self.items_url = reverse("list-items-list", kwargs={"list_id": self.list.id})

    @patch("apps.lists.views.broadcast_list_event")
    def test_add_item_broadcasts_item_added(self, mock_broadcast):
        response = self.client.post(
            self.items_url, {"name": "Eggs"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        mock_broadcast.assert_called_once()
        list_id, event, payload = mock_broadcast.call_args[0]
        self.assertEqual(list_id, self.list.id)
        self.assertEqual(event, "item.added")
        self.assertEqual(payload["name"], "Eggs")

    @patch("apps.lists.views.broadcast_list_event")
    def test_check_item_broadcasts_item_checked_not_item_updated(self, mock_broadcast):
        item = ListItem.objects.create(list=self.list, name="Bread")
        url = reverse(
            "list-items-detail", kwargs={"list_id": self.list.id, "item_id": item.id}
        )
        response = self.client.patch(url, {"checked": True}, format="json")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        mock_broadcast.assert_called_once()
        _list_id, event, payload = mock_broadcast.call_args[0]
        self.assertEqual(event, "item.checked")
        self.assertTrue(payload["checked"])

    @patch("apps.lists.views.broadcast_list_event")
    def test_edit_item_name_broadcasts_item_updated(self, mock_broadcast):
        item = ListItem.objects.create(list=self.list, name="Bread")
        url = reverse(
            "list-items-detail", kwargs={"list_id": self.list.id, "item_id": item.id}
        )
        response = self.client.patch(url, {"name": "Rye bread"}, format="json")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        _list_id, event, payload = mock_broadcast.call_args[0]
        self.assertEqual(event, "item.updated")
        self.assertEqual(payload["name"], "Rye bread")

    @patch("apps.lists.views.broadcast_list_event")
    def test_remove_item_broadcasts_item_removed(self, mock_broadcast):
        item = ListItem.objects.create(list=self.list, name="Bread")
        url = reverse(
            "list-items-detail", kwargs={"list_id": self.list.id, "item_id": item.id}
        )
        response = self.client.delete(url)
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        _list_id, event, payload = mock_broadcast.call_args[0]
        self.assertEqual(event, "item.removed")
        self.assertEqual(payload["id"], str(item.id))

    @patch("apps.lists.views.broadcast_list_event")
    def test_share_list_broadcasts_collaborator_joined(self, mock_broadcast):
        friend = User.objects.create_user(
            username="friend2@example.com",
            email="friend2@example.com",
            password="a-strong-passw0rd!",
        )
        url = reverse("list-collaborators-list", kwargs={"list_id": self.list.id})
        response = self.client.post(
            url, {"email": friend.email, "permission": "edit"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        list_id, event, payload = mock_broadcast.call_args[0]
        self.assertEqual(list_id, self.list.id)
        self.assertEqual(event, "collaborator.joined")
        self.assertEqual(payload["user_email"], friend.email)


class FieldConflictResolutionTests(APITestCase):
    """Traces to SRS FR-3.2/FR-4.2, QA Test Plan TC-3.5/TC-4.5: conflicting
    (offline-queued) edits to the same item resolve deterministically,
    field by field, rather than one wholesale clobbering the other.
    """

    def setUp(self):
        self.owner = User.objects.create_user(
            username="conflict-owner@example.com",
            email="conflict-owner@example.com",
            password="a-strong-passw0rd!",
        )
        self.client.force_authenticate(self.owner)
        self.list = ShoppingList.objects.create(
            owner=self.owner, title="Weekend", category=ListCategory.GROCERIES
        )
        self.item = ListItem.objects.create(
            list=self.list, name="Bread", quantity=1, note="original"
        )
        self.url = reverse(
            "list-items-detail",
            kwargs={"list_id": self.list.id, "item_id": self.item.id},
        )

    def test_newer_client_edit_overwrites_older_field(self):
        now = timezone.now()
        response = self.client.patch(
            self.url,
            {"note": "from phone", "client_updated_at": now.isoformat()},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["note"], "from phone")

    def test_older_queued_edit_loses_to_an_already_applied_newer_one(self):
        now = timezone.now()
        # A newer edit lands first (e.g. it was made online, immediately).
        self.client.patch(
            self.url,
            {"note": "from phone", "client_updated_at": now.isoformat()},
            format="json",
        )
        # An older, offline-queued edit to the *same field* arrives later
        # but was made earlier -- it must not clobber the newer value.
        stale_time = now - timedelta(minutes=10)
        response = self.client.patch(
            self.url,
            {"note": "from tablet (stale)", "client_updated_at": stale_time.isoformat()},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["note"], "from phone")
        self.item.refresh_from_db()
        self.assertEqual(self.item.note, "from phone")

    def test_conflict_resolves_independently_per_field(self):
        now = timezone.now()
        self.client.patch(
            self.url,
            {"note": "from phone", "client_updated_at": now.isoformat()},
            format="json",
        )
        stale_time = now - timedelta(minutes=10)
        # This stale mutation touches a *different* field (quantity), which
        # nothing newer has touched yet, so it should still apply even
        # though its timestamp lost on "note" above.
        response = self.client.patch(
            self.url,
            {
                "note": "from tablet (stale)",
                "quantity": "3.00",
                "client_updated_at": stale_time.isoformat(),
            },
            format="json",
        )
        self.assertEqual(response.data["note"], "from phone")
        self.assertEqual(response.data["quantity"], "3.00")

    @patch("apps.lists.views.broadcast_list_event")
    def test_fully_stale_edit_is_a_silent_no_op(self, mock_broadcast):
        now = timezone.now()
        self.client.patch(
            self.url,
            {"note": "from phone", "client_updated_at": now.isoformat()},
            format="json",
        )
        mock_broadcast.reset_mock()

        stale_time = now - timedelta(minutes=10)
        response = self.client.patch(
            self.url,
            {"note": "too late", "client_updated_at": stale_time.isoformat()},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["note"], "from phone")
        mock_broadcast.assert_not_called()

    def test_edit_without_client_updated_at_always_applies(self):
        """A normal online edit (no offline queue involved) has no
        client_updated_at and should behave exactly as before."""
        response = self.client.patch(self.url, {"note": "quick edit"}, format="json")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["note"], "quick edit")


class ListComparisonTests(APITestCase):
    """TC-5.4: GET /lists/{id}/comparison ranks stores by total and
    reports the savings of choosing the best one over the next best."""

    def setUp(self):
        from apps.price_intelligence.models import CurrentPrice, Confidence, Product, Store

        self.Product = Product
        self.Store = Store
        self.CurrentPrice = CurrentPrice
        self.Confidence = Confidence

        self.user = User.objects.create_user(
            username="shopper@example.com",
            email="shopper@example.com",
            password="a-strong-passw0rd!",
        )
        self.client.force_authenticate(self.user)

        self.milk = Product.objects.create(name="Full cream milk 2L")
        self.bread = Product.objects.create(name="White bread")
        self.store_a = Store.objects.create(name="Store A")
        self.store_b = Store.objects.create(name="Store B")
        self.store_c = Store.objects.create(name="Store C")  # partially priced

        self.list = ShoppingList.objects.create(owner=self.user, title="Groceries")
        ListItem.objects.create(
            list=self.list, name="Milk", quantity=2, product_id=self.milk.id
        )
        ListItem.objects.create(
            list=self.list, name="Bread", quantity=1, product_id=self.bread.id
        )
        # A free-text item with no product_id -- can't be priced, must be
        # excluded from the comparison rather than blocking it entirely.
        ListItem.objects.create(list=self.list, name="Whatever's on promo", quantity=1)

        CurrentPrice.objects.create(
            product=self.milk, store=self.store_a, price=2000, confidence=Confidence.HIGH
        )
        CurrentPrice.objects.create(
            product=self.bread, store=self.store_a, price=1800, confidence=Confidence.HIGH
        )
        CurrentPrice.objects.create(
            product=self.milk, store=self.store_b, price=2200, confidence=Confidence.MEDIUM
        )
        CurrentPrice.objects.create(
            product=self.bread, store=self.store_b, price=1750, confidence=Confidence.LOW
        )
        # Store C only has milk priced -- must be excluded, not shown
        # with a partial/incorrect total.
        CurrentPrice.objects.create(
            product=self.milk, store=self.store_c, price=1500, confidence=Confidence.HIGH
        )

        self.url = reverse("list-comparison", args=[self.list.id])

    def test_ranks_fully_priced_stores_by_total_and_computes_savings(self):
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)

        store_ids = [entry["store_id"] for entry in response.data["stores"]]
        self.assertEqual(len(response.data["stores"]), 2)  # store_c excluded
        self.assertNotIn(self.store_c.id, store_ids)

        # Store A total: 2 * 2000 + 1 * 1800 = 5800
        # Store B total: 2 * 2200 + 1 * 1750 = 6150
        self.assertEqual(response.data["stores"][0]["store_id"], self.store_a.id)
        self.assertEqual(response.data["stores"][0]["total"], 5800)
        self.assertEqual(response.data["stores"][1]["store_id"], self.store_b.id)
        self.assertEqual(response.data["stores"][1]["total"], 6150)

        self.assertEqual(response.data["best"]["store_id"], self.store_a.id)
        self.assertEqual(response.data["best"]["saves"], 350)

    def test_weakest_confidence_across_priced_items_is_reported_per_store(self):
        response = self.client.get(self.url)
        by_store = {entry["store_id"]: entry for entry in response.data["stores"]}
        # Store B's bread price is LOW confidence -- that should pull the
        # whole store's reported confidence down to LOW even though its
        # milk price is MEDIUM.
        self.assertEqual(by_store[self.store_b.id]["confidence"], "low")
        self.assertEqual(by_store[self.store_a.id]["confidence"], "high")

    def test_view_only_collaborator_can_read_comparison(self):
        from apps.lists.models import CollaboratorPermission, ListCollaborator

        viewer = User.objects.create_user(
            username="viewer@example.com",
            email="viewer@example.com",
            password="a-strong-passw0rd!",
        )
        ListCollaborator.objects.create(
            list=self.list, user=viewer, permission=CollaboratorPermission.VIEW
        )
        self.client.force_authenticate(viewer)

        response = self.client.get(self.url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def test_user_with_no_access_gets_404(self):
        outsider = User.objects.create_user(
            username="outsider@example.com",
            email="outsider@example.com",
            password="a-strong-passw0rd!",
        )
        self.client.force_authenticate(outsider)
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_list_with_no_priced_items_returns_empty_comparison(self):
        empty_list = ShoppingList.objects.create(owner=self.user, title="Empty")
        ListItem.objects.create(list=empty_list, name="Mystery item", quantity=1)
        url = reverse("list-comparison", args=[empty_list.id])

        response = self.client.get(url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data["stores"], [])
        self.assertIsNone(response.data["best"])


class ImplicitPriceObservationTests(APITestCase):
    """FR-5.4: checking off an item with a paid price and a store submits
    a crowd-sourced price observation through the same ingestion path as
    POST /prices/observations."""

    def setUp(self):
        from apps.price_intelligence.models import (
            Confidence,
            CurrentPrice,
            PriceObservation,
            PriceSource,
            Product,
            Store,
        )

        self.PriceObservation = PriceObservation
        self.CurrentPrice = CurrentPrice
        self.Confidence = Confidence
        self.PriceSource = PriceSource

        self.user = User.objects.create_user(
            username="shopper@example.com",
            email="shopper@example.com",
            password="a-strong-passw0rd!",
        )
        self.client.force_authenticate(self.user)

        self.product = Product.objects.create(name="Full cream milk 2L")
        self.store = Store.objects.create(name="Store A")

        self.list = ShoppingList.objects.create(owner=self.user, title="Groceries")
        self.item = ListItem.objects.create(
            list=self.list, name="Milk", quantity=1, product_id=self.product.id
        )
        self.url = reverse(
            "list-items-detail", kwargs={"list_id": self.list.id, "item_id": self.item.id}
        )

    def test_check_off_with_price_and_store_creates_observation(self):
        response = self.client.patch(
            self.url,
            {"checked": True, "paid_price": 2599, "store_id": str(self.store.id)},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)

        observation = self.PriceObservation.objects.get(
            product=self.product, store=self.store
        )
        self.assertEqual(observation.price, 2599)
        self.assertEqual(observation.submitted_by, self.user)
        self.assertFalse(observation.is_quarantined)

        current = self.CurrentPrice.objects.get(product=self.product, store=self.store)
        self.assertEqual(current.price, 2599)

    def test_store_id_is_not_persisted_on_the_item(self):
        response = self.client.patch(
            self.url,
            {"checked": True, "paid_price": 2599, "store_id": str(self.store.id)},
            format="json",
        )
        self.assertNotIn("store_id", response.data)

    def test_check_off_without_store_id_does_not_create_observation(self):
        """Backward-compatible with clients that don't yet send store_id
        (existing app behaviour until it's wired up)."""
        self.client.patch(
            self.url, {"checked": True, "paid_price": 2599}, format="json"
        )
        self.assertEqual(self.PriceObservation.objects.count(), 0)

    def test_check_off_without_product_id_does_not_create_observation(self):
        free_text_item = ListItem.objects.create(list=self.list, name="Whatever's on promo")
        url = reverse(
            "list-items-detail",
            kwargs={"list_id": self.list.id, "item_id": free_text_item.id},
        )
        self.client.patch(
            url,
            {"checked": True, "paid_price": 500, "store_id": str(self.store.id)},
            format="json",
        )
        self.assertEqual(self.PriceObservation.objects.count(), 0)

    def test_unrecognized_store_id_does_not_error(self):
        import uuid

        response = self.client.patch(
            self.url,
            {"checked": True, "paid_price": 2599, "store_id": str(uuid.uuid4())},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(self.PriceObservation.objects.count(), 0)

    def test_extreme_outlier_paid_price_is_quarantined(self):
        self.CurrentPrice.objects.create(
            product=self.product,
            store=self.store,
            price=2500,
            confidence=self.Confidence.HIGH,
        )
        self.PriceObservation.objects.create(
            product=self.product,
            store=self.store,
            price=2500,
            source=self.PriceSource.STORE,
            observed_at=timezone.now(),
        )
        response = self.client.patch(
            self.url,
            {"checked": True, "paid_price": 1, "store_id": str(self.store.id)},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        outlier = self.PriceObservation.objects.get(price=1)
        self.assertTrue(outlier.is_quarantined)


class PromotionFlagOnItemTests(APITestCase):
    """SRS FR-7.2: items linked to a promoted product are flagged
    non-intrusively (has_promotion) in list/item views."""

    def setUp(self):
        from apps.price_intelligence.models import Product, Store
        from apps.promotions.models import Promotion

        self.user = User.objects.create_user(
            username="shopper@example.com",
            email="shopper@example.com",
            password="a-strong-passw0rd!",
        )
        self.client.force_authenticate(self.user)

        self.milk = Product.objects.create(name="Full cream milk 2L")
        store = Store.objects.create(name="Store A")

        self.list = ShoppingList.objects.create(owner=self.user, title="Groceries")
        self.promoted_item = ListItem.objects.create(
            list=self.list, name="Milk", quantity=1, product_id=self.milk.id
        )
        self.plain_item = ListItem.objects.create(
            list=self.list, name="Whatever's on promo", quantity=1
        )

        Promotion.objects.create(store=store, product=self.milk, title="20% off milk")

        self.items_url = reverse("list-items-list", kwargs={"list_id": self.list.id})

    def _item_url(self, item_id):
        return reverse(
            "list-items-detail", kwargs={"list_id": self.list.id, "item_id": item_id}
        )

    def test_list_items_flags_promoted_item_only(self):
        response = self.client.get(self.items_url)
        by_id = {item["id"]: item for item in response.data["results"]}
        self.assertTrue(by_id[str(self.promoted_item.id)]["has_promotion"])
        self.assertFalse(by_id[str(self.plain_item.id)]["has_promotion"])

    def test_item_detail_reflects_flag(self):
        response = self.client.get(self._item_url(self.promoted_item.id))
        self.assertTrue(response.data["has_promotion"])

    def test_flag_disappears_once_opted_out(self):
        from apps.promotions.models import Promotion

        promo = Promotion.objects.get(product_id=self.milk.id)
        self.client.post(
            reverse("promotions-opt-out"),
            {"store_id": str(promo.store_id)},
            format="json",
        )
        response = self.client.get(self._item_url(self.promoted_item.id))
        self.assertFalse(response.data["has_promotion"])

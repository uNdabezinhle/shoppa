"""SRS §3.8 Professional Tools. QA Test Plan §5.8: TC-8.1 (scale by
guest count), TC-8.2 (publish + clone -- lands with the publish
commit).
"""
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from apps.users.models import AccountType, User

from .models import ListCategory, ListItem, ShoppingList


class ListDuplicateTests(APITestCase):
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

        self.source = ShoppingList.objects.create(
            owner=self.user, title="Braai supplies", category=ListCategory.GROCERIES
        )
        ListItem.objects.create(
            list=self.source, name="Boerewors", quantity=2, unit="kg", checked=True,
            paid_price=15000,
        )
        self.url = reverse("lists-duplicate", kwargs={"pk": self.source.id})

    def test_duplicate_creates_a_new_list_owned_by_caller(self):
        response = self.client.post(self.url)
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertNotEqual(response.data["id"], str(self.source.id))

        clone = ShoppingList.objects.get(id=response.data["id"])
        self.assertEqual(clone.owner, self.user)
        self.assertEqual(clone.title, self.source.title)

    def test_duplicate_copies_items_but_resets_checked_and_price(self):
        response = self.client.post(self.url)
        clone = ShoppingList.objects.get(id=response.data["id"])
        item = clone.items.get(name="Boerewors")
        self.assertEqual(item.quantity, 2)
        self.assertFalse(item.checked)
        self.assertIsNone(item.paid_price)

    def test_user_with_no_access_cannot_duplicate(self):
        self.client.force_authenticate(self.other_user)
        response = self.client.post(self.url)
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_duplicate_respects_owned_list_quota(self):
        """Free tier max owned lists applies to clone as well as create."""
        from apps.subscriptions.services import owned_list_limit

        limit = owned_list_limit(self.user)
        if limit is None:
            self.skipTest("no owned-list limit configured")
        # user already owns self.source; fill to the free-tier cap
        for i in range(limit - 1):
            ShoppingList.objects.create(
                owner=self.user,
                title=f"Filler {i}",
                category=ListCategory.GROCERIES,
            )
        response = self.client.post(self.url)
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)


class ListScaleTests(APITestCase):
    """TC-8.1: scaling a list by guest count adjusts all quantities
    correctly."""

    def setUp(self):
        self.pro_user = User.objects.create_user(
            username="chef@example.com",
            email="chef@example.com",
            password="a-strong-passw0rd!",
            account_type=AccountType.PROFESSIONAL,
        )
        self.personal_user = User.objects.create_user(
            username="shopper@example.com",
            email="shopper@example.com",
            password="a-strong-passw0rd!",
            account_type=AccountType.PERSONAL,
        )
        self.list = ShoppingList.objects.create(
            owner=self.pro_user, title="Braai for 10", category=ListCategory.EVENT
        )
        self.milk = ListItem.objects.create(
            list=self.list, name="Milk", quantity=2, unit="ea"
        )
        self.bread = ListItem.objects.create(
            list=self.list, name="Bread", quantity=3, unit="ea"
        )
        self.url = reverse("lists-scale", kwargs={"pk": self.list.id})

    def test_professional_owner_scales_by_factor(self):
        self.client.force_authenticate(self.pro_user)
        response = self.client.post(self.url, {"factor": 2.5}, format="json")
        self.assertEqual(response.status_code, status.HTTP_200_OK)

        self.milk.refresh_from_db()
        self.bread.refresh_from_db()
        self.assertEqual(self.milk.quantity, 5)
        self.assertEqual(self.bread.quantity, 7.5)

    def test_professional_owner_scales_by_guest_count(self):
        self.client.force_authenticate(self.pro_user)
        response = self.client.post(self.url, {"guests": 5}, format="json")
        self.assertEqual(response.status_code, status.HTTP_200_OK)

        self.milk.refresh_from_db()
        self.bread.refresh_from_db()
        self.assertEqual(self.milk.quantity, 10)
        self.assertEqual(self.bread.quantity, 15)

    def test_personal_account_cannot_scale(self):
        other_list = ShoppingList.objects.create(
            owner=self.personal_user, title="My list", category=ListCategory.CUSTOM
        )
        self.client.force_authenticate(self.personal_user)
        url = reverse("lists-scale", kwargs={"pk": other_list.id})
        response = self.client.post(url, {"factor": 2}, format="json")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_non_owner_professional_collaborator_cannot_scale(self):
        from .models import CollaboratorPermission, ListCollaborator

        pro_collaborator = User.objects.create_user(
            username="pro2@example.com",
            email="pro2@example.com",
            password="a-strong-passw0rd!",
            account_type=AccountType.PROFESSIONAL,
        )
        ListCollaborator.objects.create(
            list=self.list, user=pro_collaborator, permission=CollaboratorPermission.EDIT
        )
        self.client.force_authenticate(pro_collaborator)
        response = self.client.post(self.url, {"factor": 2}, format="json")
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_requires_exactly_one_of_factor_or_guests(self):
        self.client.force_authenticate(self.pro_user)
        response = self.client.post(self.url, {}, format="json")
        self.assertEqual(response.status_code, 422)

        response = self.client.post(
            self.url, {"factor": 2, "guests": 5}, format="json"
        )
        self.assertEqual(response.status_code, 422)

    def test_rejects_non_positive_multiplier(self):
        self.client.force_authenticate(self.pro_user)
        response = self.client.post(self.url, {"factor": 0}, format="json")
        self.assertEqual(response.status_code, 422)

    def test_scale_logs_activity(self):
        from .models import ListActivity, ListActivityAction

        self.client.force_authenticate(self.pro_user)
        self.client.post(self.url, {"factor": 2}, format="json")
        self.assertTrue(
            ListActivity.objects.filter(
                list=self.list, action=ListActivityAction.LIST_SCALED
            ).exists()
        )


class ListPublishTests(APITestCase):
    """TC-8.2: published list is discoverable and can be cloned by
    another user."""

    def setUp(self):
        self.pro_user = User.objects.create_user(
            username="chef@example.com",
            email="chef@example.com",
            password="a-strong-passw0rd!",
            account_type=AccountType.PROFESSIONAL,
        )
        self.other_user = User.objects.create_user(
            username="shopper@example.com",
            email="shopper@example.com",
            password="a-strong-passw0rd!",
        )
        self.list = ShoppingList.objects.create(
            owner=self.pro_user, title="Wedding catering", category=ListCategory.EVENT
        )
        ListItem.objects.create(list=self.list, name="Rice", quantity=10, unit="kg")
        self.detail_url = reverse("lists-detail", kwargs={"pk": self.list.id})
        self.public_url = reverse("lists-public")

    def test_professional_can_publish_a_list(self):
        self.client.force_authenticate(self.pro_user)
        response = self.client.patch(
            self.detail_url, {"is_public": True}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.list.refresh_from_db()
        self.assertTrue(self.list.is_public)

    def test_personal_account_cannot_publish(self):
        personal_user = User.objects.create_user(
            username="personal@example.com",
            email="personal@example.com",
            password="a-strong-passw0rd!",
        )
        own_list = ShoppingList.objects.create(owner=personal_user, title="My list")
        self.client.force_authenticate(personal_user)
        url = reverse("lists-detail", kwargs={"pk": own_list.id})
        response = self.client.patch(url, {"is_public": True}, format="json")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_published_list_is_discoverable_by_other_users(self):
        self.list.is_public = True
        self.list.save()
        self.client.force_authenticate(self.other_user)

        response = self.client.get(self.public_url)
        list_ids = {entry["id"] for entry in response.data["results"]}
        self.assertIn(str(self.list.id), list_ids)

    def test_unpublished_list_is_not_discoverable(self):
        self.client.force_authenticate(self.other_user)
        response = self.client.get(self.public_url)
        list_ids = {entry["id"] for entry in response.data["results"]}
        self.assertNotIn(str(self.list.id), list_ids)

    def test_public_endpoint_excludes_own_lists(self):
        self.list.is_public = True
        self.list.save()
        self.client.force_authenticate(self.pro_user)
        response = self.client.get(self.public_url)
        list_ids = {entry["id"] for entry in response.data["results"]}
        self.assertNotIn(str(self.list.id), list_ids)

    def test_other_user_can_clone_a_published_list(self):
        self.list.is_public = True
        self.list.save()
        self.client.force_authenticate(self.other_user)

        duplicate_url = reverse("lists-duplicate", kwargs={"pk": self.list.id})
        response = self.client.post(duplicate_url)
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

        clone = ShoppingList.objects.get(id=response.data["id"])
        self.assertEqual(clone.owner, self.other_user)
        self.assertEqual(clone.items.get(name="Rice").quantity, 10)

    def test_other_user_cannot_clone_an_unpublished_list(self):
        self.client.force_authenticate(self.other_user)
        duplicate_url = reverse("lists-duplicate", kwargs={"pk": self.list.id})
        response = self.client.post(duplicate_url)
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)


class ListEventAttachmentTests(APITestCase):
    """FR-8.3: attach a list to a named event with a date."""

    def setUp(self):
        self.pro_user = User.objects.create_user(
            username="planner@example.com",
            email="planner@example.com",
            password="a-strong-passw0rd!",
            account_type=AccountType.PROFESSIONAL,
        )
        self.personal_user = User.objects.create_user(
            username="shopper2@example.com",
            email="shopper2@example.com",
            password="a-strong-passw0rd!",
        )
        self.pro_list = ShoppingList.objects.create(
            owner=self.pro_user, title="Corporate launch", category=ListCategory.EVENT
        )
        self.personal_list = ShoppingList.objects.create(
            owner=self.personal_user, title="Birthday"
        )

    def test_professional_can_attach_event_name_and_date(self):
        self.client.force_authenticate(self.pro_user)
        url = reverse("lists-detail", kwargs={"pk": self.pro_list.id})
        response = self.client.patch(
            url,
            {"event_name": "Product Launch", "event_date": "2026-08-01"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.pro_list.refresh_from_db()
        self.assertEqual(self.pro_list.event_name, "Product Launch")
        self.assertEqual(str(self.pro_list.event_date), "2026-08-01")

    def test_personal_account_cannot_attach_event_fields(self):
        self.client.force_authenticate(self.personal_user)
        url = reverse("lists-detail", kwargs={"pk": self.personal_list.id})
        response = self.client.patch(
            url, {"event_name": "Birthday Bash"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_non_event_fields_still_patchable_by_personal_accounts(self):
        """Regression guard: the professional gate must not block ordinary
        PATCHes (e.g. title) for Personal accounts."""
        self.client.force_authenticate(self.personal_user)
        url = reverse("lists-detail", kwargs={"pk": self.personal_list.id})
        response = self.client.patch(url, {"title": "New title"}, format="json")
        self.assertEqual(response.status_code, status.HTTP_200_OK)


class ListExportTests(APITestCase):
    """TC-8.3: export produces valid PDF and CSV of the list."""

    def setUp(self):
        self.user = User.objects.create_user(
            username="shopper3@example.com",
            email="shopper3@example.com",
            password="a-strong-passw0rd!",
        )
        self.other_user = User.objects.create_user(
            username="outsider@example.com",
            email="outsider@example.com",
            password="a-strong-passw0rd!",
        )
        self.client.force_authenticate(self.user)
        self.list = ShoppingList.objects.create(owner=self.user, title="Groceries")
        ListItem.objects.create(
            list=self.list, name="Milk", quantity=2, unit="ea", checked=True,
            paid_price=2599,
        )
        self.url = reverse("lists-export", kwargs={"pk": self.list.id})

    def test_csv_export_contains_item_rows(self):
        response = self.client.get(self.url, {"type": "csv"})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response["Content-Type"], "text/csv")
        body = response.content.decode("utf-8")
        self.assertIn("Milk", body)
        self.assertIn("25.99", body)

    def test_csv_is_the_default_format(self):
        response = self.client.get(self.url)
        self.assertEqual(response["Content-Type"], "text/csv")

    def test_pdf_export_produces_a_valid_pdf(self):
        response = self.client.get(self.url, {"type": "pdf"})
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response["Content-Type"], "application/pdf")
        # A real PDF always starts with this magic header.
        self.assertTrue(response.content.startswith(b"%PDF"))

    def test_invalid_format_is_rejected(self):
        response = self.client.get(self.url, {"type": "docx"})
        self.assertEqual(response.status_code, 422)

    def test_user_with_no_access_cannot_export(self):
        self.client.force_authenticate(self.other_user)
        response = self.client.get(self.url, {"type": "csv"})
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

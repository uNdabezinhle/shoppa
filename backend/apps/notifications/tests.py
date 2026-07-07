"""TC-5.5: price-drop notifications surface in the in-app feed."""
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from apps.lists.models import ListItem, ShoppingList
from apps.notifications.models import Notification
from apps.price_intelligence.models import PriceSource
from apps.price_intelligence.services import record_observation
from apps.users.models import User


class PriceDropNotificationTests(APITestCase):
    def setUp(self):
        from apps.price_intelligence.models import Product, Store

        self.user = User.objects.create_user(
            username="notify@example.com",
            email="notify@example.com",
            password="pw12345!",
        )
        self.product = Product.objects.create(name="Full cream milk 2L", region="ZA")
        self.store = Store.objects.create(name="Checkers", region="ZA")
        shopping_list = ShoppingList.objects.create(owner=self.user, title="Groceries")
        ListItem.objects.create(
            list=shopping_list,
            name="Milk",
            quantity=1,
            product_id=self.product.id,
        )
        self.client.force_authenticate(self.user)

    def test_qualifying_drop_creates_in_app_notification(self):
        record_observation(
            product=self.product,
            store=self.store,
            price=3000,
            source=PriceSource.STORE,
        )
        record_observation(
            product=self.product,
            store=self.store,
            price=2000,
            source=PriceSource.STORE,
        )

        notifications = Notification.objects.filter(user=self.user)
        self.assertEqual(notifications.count(), 1)
        note = notifications.first()
        self.assertEqual(note.kind, "price_drop")
        self.assertIn("Full cream milk 2L", note.title)

        response = self.client.get(reverse("notifications-list"))
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data["results"]), 1)
        self.assertFalse(response.data["results"][0]["is_read"])

    def test_mark_notification_read(self):
        record_observation(
            product=self.product,
            store=self.store,
            price=3000,
            source=PriceSource.STORE,
        )
        record_observation(
            product=self.product,
            store=self.store,
            price=2000,
            source=PriceSource.STORE,
        )
        note = Notification.objects.get(user=self.user)
        url = reverse("notifications-read", kwargs={"pk": note.id})
        response = self.client.patch(url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data["is_read"])
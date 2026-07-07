"""QA Test Plan §5.7: TC-7.1 (targeting matches only users with the
product on a list) and TC-7.2 (opting out of a store suppresses its
promotions). Also covers category opt-out and the create-time exactly-
one-target validation (FR-7.3).
"""
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APITestCase

from apps.lists.models import ListItem, ShoppingList
from apps.price_intelligence.models import Product, Store
from apps.users.models import User

from .models import Promotion, PromotionOptOut
from .services import has_active_promotion


class PromotionTargetingTests(APITestCase):
    """TC-7.1."""

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

        self.milk = Product.objects.create(name="Full cream milk 2L")
        self.bread = Product.objects.create(name="White bread")
        self.store = Store.objects.create(name="Store A")

        self.milk_promo = Promotion.objects.create(
            store=self.store,
            product=self.milk,
            title="20% off milk",
            category="groceries",
        )
        # Bread promotion exists too, but only self.user has bread on a
        # list -- this is the negative case for the "only matching
        # products" half of TC-7.1.
        self.bread_promo = Promotion.objects.create(
            store=self.store, product=self.bread, title="Bread special"
        )

        shopping_list = ShoppingList.objects.create(owner=self.user, title="Groceries")
        ListItem.objects.create(
            list=shopping_list, name="Milk", quantity=1, product_id=self.milk.id
        )

        self.url = reverse("promotions-list")

    def test_targets_only_users_with_the_product_on_a_list(self):
        response = self.client.get(self.url)
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        promo_ids = {p["id"] for p in response.data["results"]}
        self.assertIn(str(self.milk_promo.id), promo_ids)
        self.assertNotIn(str(self.bread_promo.id), promo_ids)

    def test_user_with_no_matching_products_sees_no_promotions(self):
        self.client.force_authenticate(self.other_user)
        response = self.client.get(self.url)
        self.assertEqual(response.data["results"], [])

    def test_promotion_on_shared_list_item_is_visible_to_collaborator(self):
        from apps.lists.models import CollaboratorPermission, ListCollaborator

        shopping_list = ShoppingList.objects.create(owner=self.user, title="Shared")
        ListItem.objects.create(
            list=shopping_list, name="Bread", quantity=1, product_id=self.bread.id
        )
        ListCollaborator.objects.create(
            list=shopping_list, user=self.other_user, permission=CollaboratorPermission.VIEW
        )
        self.client.force_authenticate(self.other_user)

        response = self.client.get(self.url)
        promo_ids = {p["id"] for p in response.data["results"]}
        self.assertIn(str(self.bread_promo.id), promo_ids)

    def test_inactive_promotion_is_excluded(self):
        self.milk_promo.is_active = False
        self.milk_promo.save()
        self.assertFalse(has_active_promotion(self.user, self.milk.id))

    def test_expired_promotion_is_excluded(self):
        self.milk_promo.ends_at = timezone.now() - timezone.timedelta(days=1)
        self.milk_promo.save()
        self.assertFalse(has_active_promotion(self.user, self.milk.id))

    def test_not_yet_started_promotion_is_excluded(self):
        self.milk_promo.starts_at = timezone.now() + timezone.timedelta(days=1)
        self.milk_promo.save()
        self.assertFalse(has_active_promotion(self.user, self.milk.id))

    def test_has_active_promotion_true_for_targeted_product(self):
        self.assertTrue(has_active_promotion(self.user, self.milk.id))

    def test_has_active_promotion_false_for_untargeted_product(self):
        untargeted = Product.objects.create(name="Rice")
        Promotion.objects.create(store=self.store, product=untargeted, title="Rice deal")
        self.assertFalse(has_active_promotion(self.user, untargeted.id))


class PromotionOptOutTests(APITestCase):
    """TC-7.2, plus category opt-out and validation."""

    def setUp(self):
        self.user = User.objects.create_user(
            username="shopper@example.com",
            email="shopper@example.com",
            password="a-strong-passw0rd!",
        )
        self.client.force_authenticate(self.user)

        self.milk = Product.objects.create(name="Full cream milk 2L")
        self.store = Store.objects.create(name="Store A")
        self.other_store = Store.objects.create(name="Store B")

        self.promo = Promotion.objects.create(
            store=self.store, product=self.milk, title="20% off milk", category="groceries"
        )

        shopping_list = ShoppingList.objects.create(owner=self.user, title="Groceries")
        ListItem.objects.create(
            list=shopping_list, name="Milk", quantity=1, product_id=self.milk.id
        )

        self.promotions_url = reverse("promotions-list")
        self.opt_out_url = reverse("promotions-opt-out")

    def test_opting_out_of_a_store_suppresses_its_promotions(self):
        response = self.client.post(
            self.opt_out_url, {"store_id": str(self.store.id)}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

        promos = self.client.get(self.promotions_url).data["results"]
        self.assertEqual(promos, [])

    def test_opting_out_of_a_category_suppresses_matching_promotions(self):
        response = self.client.post(
            self.opt_out_url, {"category": "groceries"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)

        promos = self.client.get(self.promotions_url).data["results"]
        self.assertEqual(promos, [])

    def test_opting_out_of_a_different_store_does_not_suppress(self):
        self.client.post(
            self.opt_out_url, {"store_id": str(self.other_store.id)}, format="json"
        )
        promos = self.client.get(self.promotions_url).data["results"]
        self.assertEqual(len(promos), 1)

    def test_opt_out_is_idempotent(self):
        for _ in range(2):
            response = self.client.post(
                self.opt_out_url, {"store_id": str(self.store.id)}, format="json"
            )
            self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(
            PromotionOptOut.objects.filter(user=self.user, store=self.store).count(), 1
        )

    def test_opt_out_requires_exactly_one_target(self):
        response = self.client.post(self.opt_out_url, {}, format="json")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_opt_out_rejects_both_store_and_category(self):
        response = self.client.post(
            self.opt_out_url,
            {"store_id": str(self.store.id), "category": "groceries"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_opt_out_is_per_user(self):
        other_user = User.objects.create_user(
            username="other@example.com",
            email="other@example.com",
            password="a-strong-passw0rd!",
        )
        self.client.post(self.opt_out_url, {"store_id": str(self.store.id)}, format="json")

        self.assertFalse(has_active_promotion(other_user, self.milk.id))  # no list item yet
        other_list = ShoppingList.objects.create(owner=other_user, title="List")
        ListItem.objects.create(list=other_list, name="Milk", quantity=1, product_id=self.milk.id)
        self.assertTrue(has_active_promotion(other_user, self.milk.id))

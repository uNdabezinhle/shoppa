"""Keep Typesense index in sync with Product rows (M8)."""
from django.db.models.signals import post_delete, post_save
from django.dispatch import receiver

from .models import Product
from .search import delete_product, upsert_product


@receiver(post_save, sender=Product)
def product_saved(sender, instance, **kwargs):
    upsert_product(instance.id, instance.name, instance.region)


@receiver(post_delete, sender=Product)
def product_deleted(sender, instance, **kwargs):
    delete_product(instance.id)

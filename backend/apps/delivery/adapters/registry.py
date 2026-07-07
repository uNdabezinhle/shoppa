"""Adapter registry — new platforms plug in without core changes (FR-6.4)."""
from django.conf import settings

from .base import DeliveryAdapter
from .seeded import build_seeded_adapter

_REGISTRY: dict[str, DeliveryAdapter] = {}


def _bootstrap_registry():
    if _REGISTRY:
        return
    for platform_id in (
        "checkers_6060",
        "pnp_asap",
        "spar_2u",
        "woolies_dash",
    ):
        register_adapter(build_seeded_adapter(platform_id))


def register_adapter(adapter: DeliveryAdapter) -> None:
    _REGISTRY[adapter.platform_id] = adapter


def get_adapters_for_region(region: str) -> list[DeliveryAdapter]:
    _bootstrap_registry()
    enabled = settings.DELIVERY_PLATFORMS_BY_REGION.get(region, [])
    return [_REGISTRY[platform_id] for platform_id in enabled if platform_id in _REGISTRY]
"""Common delivery adapter interface (Architecture §7, FR-6.4)."""
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Sequence
from uuid import UUID


@dataclass(frozen=True)
class DeliveryItem:
    product_id: UUID
    quantity: float
    name: str


@dataclass
class DeliveryQuoteResult:
    platform: str
    display_name: str
    subtotal: int
    delivery_fee: int
    total: int
    eta_minutes: int
    available_items: int
    total_items: int
    order_url: str


class DeliveryAdapter(ABC):
    """Each launch platform implements this contract."""

    platform_id: str
    display_name: str

    @abstractmethod
    def quote(
        self,
        items: Sequence[DeliveryItem],
        *,
        region: str,
        list_id: UUID,
    ) -> DeliveryQuoteResult:
        """Return availability, basket total, ETA, and affiliate order URL."""
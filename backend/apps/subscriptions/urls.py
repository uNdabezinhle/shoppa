from django.urls import path

from .views import (
    StripeWebhookView,
    SubscriptionCheckoutView,
    SubscriptionMeView,
    SubscriptionPlansView,
)

urlpatterns = [
    path("subscriptions/plans", SubscriptionPlansView.as_view(), name="subscriptions-plans"),
    path("subscriptions/me", SubscriptionMeView.as_view(), name="subscriptions-me"),
    path(
        "subscriptions/checkout",
        SubscriptionCheckoutView.as_view(),
        name="subscriptions-checkout",
    ),
    path("webhooks/stripe", StripeWebhookView.as_view(), name="stripe-webhook"),
]
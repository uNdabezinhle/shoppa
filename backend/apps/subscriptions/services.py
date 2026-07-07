"""Feature-flag gating and Stripe checkout helpers (FR-9.1–FR-9.3)."""
import logging
import uuid

from django.conf import settings
from django.utils import timezone

from apps.users.models import AccountType

from .models import SubscriptionPlan, UserSubscription

logger = logging.getLogger(__name__)

LAUNCH_PLANS = [
    {
        "slug": "free",
        "name": "Free",
        "price_monthly": 0,
        "features": [],
        "max_owned_lists": 3,
        "sort_order": 0,
    },
    {
        "slug": "personal_premium",
        "name": "Personal Premium",
        "price_monthly": 4900,
        "features": ["unlimited_lists", "ads_free"],
        "max_owned_lists": None,
        "sort_order": 1,
    },
    {
        "slug": "professional",
        "name": "Professional",
        "price_monthly": 9900,
        "features": [
            "unlimited_lists",
            "scale_lists",
            "publish_lists",
            "event_lists",
            "ads_free",
        ],
        "max_owned_lists": None,
        "sort_order": 2,
    },
]


def ensure_plans_seeded():
    for entry in LAUNCH_PLANS:
        SubscriptionPlan.objects.update_or_create(
            slug=entry["slug"],
            defaults={
                "name": entry["name"],
                "price_monthly": entry["price_monthly"],
                "currency_code": settings.DEFAULT_CURRENCY,
                "features": entry["features"],
                "max_owned_lists": entry["max_owned_lists"],
                "is_active": True,
                "sort_order": entry["sort_order"],
            },
        )


def ensure_user_subscription(user):
    ensure_plans_seeded()
    subscription, _ = UserSubscription.objects.get_or_create(
        user=user,
        defaults={"plan_id": "free", "status": UserSubscription.Status.ACTIVE},
    )
    return subscription


def get_active_subscription(user):
    ensure_plans_seeded()
    try:
        return user.subscription
    except UserSubscription.DoesNotExist:
        return ensure_user_subscription(user)


def user_feature_flags(user) -> set[str]:
    subscription = get_active_subscription(user)
    if subscription.status != UserSubscription.Status.ACTIVE:
        return set()
    return set(subscription.plan.features or [])


def user_has_feature(user, feature: str) -> bool:
    return feature in user_feature_flags(user)


def owned_list_limit(user):
    subscription = get_active_subscription(user)
    if subscription.status != UserSubscription.Status.ACTIVE:
        return 3
    return subscription.plan.max_owned_lists


def assert_can_create_list(user):
    from apps.lists.models import ShoppingList

    limit = owned_list_limit(user)
    if limit is None:
        return
    owned = ShoppingList.objects.filter(owner=user).count()
    if owned >= limit:
        from rest_framework.exceptions import PermissionDenied

        raise PermissionDenied(
            f"Free tier allows up to {limit} owned lists. Upgrade to create more."
        )


def create_checkout_session(user, plan: SubscriptionPlan):
    if plan.price_monthly <= 0:
        raise ValueError("Cannot checkout a free plan")

    if settings.STRIPE_SECRET_KEY:
        try:
            import stripe

            stripe.api_key = settings.STRIPE_SECRET_KEY
            session = stripe.checkout.Session.create(
                mode="subscription",
                client_reference_id=str(user.id),
                customer_email=user.email,
                metadata={"plan_id": plan.slug, "user_id": str(user.id)},
                line_items=[
                    {
                        "price_data": {
                            "currency": plan.currency_code.lower(),
                            "unit_amount": plan.price_monthly,
                            "recurring": {"interval": "month"},
                            "product_data": {"name": f"Shoppa {plan.name}"},
                        },
                        "quantity": 1,
                    }
                ],
                success_url=settings.STRIPE_CHECKOUT_SUCCESS_URL,
                cancel_url=settings.STRIPE_CHECKOUT_CANCEL_URL,
            )
            return {
                "checkout_url": session.url,
                "session_id": session.id,
                "dev_mode": False,
                "plan_id": plan.slug,
            }
        except Exception:
            logger.exception("Stripe checkout failed; falling back to dev mode")

    session_id = f"dev_cs_{uuid.uuid4().hex[:16]}"
    return {
        "checkout_url": (
            f"{settings.STRIPE_CHECKOUT_SUCCESS_URL}"
            f"?session_id={session_id}&plan_id={plan.slug}&dev=1"
        ),
        "session_id": session_id,
        "dev_mode": True,
        "plan_id": plan.slug,
    }


def activate_subscription(user, plan_slug, *, stripe_subscription_id=""):
    ensure_plans_seeded()
    plan = SubscriptionPlan.objects.get(slug=plan_slug, is_active=True)
    subscription = ensure_user_subscription(user)
    subscription.plan = plan
    subscription.status = UserSubscription.Status.ACTIVE
    subscription.stripe_subscription_id = stripe_subscription_id
    subscription.current_period_end = timezone.now() + timezone.timedelta(days=30)
    subscription.save(
        update_fields=[
            "plan",
            "status",
            "stripe_subscription_id",
            "current_period_end",
            "updated_at",
        ]
    )
    if plan_slug == "professional" and user.account_type == AccountType.PERSONAL:
        user.account_type = AccountType.PROFESSIONAL
        user.save(update_fields=["account_type"])
    return subscription


def handle_checkout_completed(event_object):
    user_id = event_object.get("client_reference_id") or event_object.get(
        "metadata", {}
    ).get("user_id")
    plan_id = event_object.get("metadata", {}).get("plan_id")
    if not user_id or not plan_id:
        logger.warning("checkout.session.completed missing user_id or plan_id")
        return None
    from apps.users.models import User

    user = User.objects.filter(pk=user_id).first()
    if user is None:
        logger.warning("checkout.session.completed user %s not found", user_id)
        return None
    stripe_sub_id = event_object.get("subscription") or ""
    return activate_subscription(user, plan_id, stripe_subscription_id=stripe_sub_id)
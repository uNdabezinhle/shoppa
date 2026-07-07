"""Placement selection, ads_free suppression, and frequency capping (FR-10)."""
from apps.subscriptions.services import user_has_feature

from .models import AdClick, AdFormat, AdImpression, AdPlacement, AdSurface

FREQUENCY_CAPPED_FORMATS = {AdFormat.INTERSTITIAL, AdFormat.REWARDED}
SESSION_CAP_PER_FORMAT = 1


def user_sees_ads(user) -> bool:
    return not user_has_feature(user, "ads_free")


def ensure_house_ads_seeded():
    launch = [
        {
            "slug": "home-pro-banner",
            "title": "Unlock unlimited lists",
            "body": "Go ad-free and scale lists for events with Shoppa Premium.",
            "cta_text": "See plans",
            "cta_url": "https://app.shoppa.app/subscriptions",
            "surface": AdSurface.HOME,
            "ad_format": AdFormat.BANNER,
            "sort_order": 0,
        },
        {
            "slug": "list-pro-banner",
            "title": "Cooking for a crowd?",
            "body": "Professional tools scale any list by guest count in one tap.",
            "cta_text": "Upgrade",
            "cta_url": "https://app.shoppa.app/subscriptions",
            "surface": AdSurface.LIST,
            "ad_format": AdFormat.BANNER,
            "sort_order": 0,
        },
        {
            "slug": "compare-dash-native",
            "title": "Try Woolworths Dash",
            "body": "Same-day delivery on your list essentials.",
            "cta_text": "Learn more",
            "cta_url": "https://www.woolworths.co.za",
            "surface": AdSurface.LIST,
            "ad_format": AdFormat.NATIVE,
            "sponsor_name": "Woolworths Dash",
            "sort_order": 1,
        },
        {
            "slug": "session-interstitial",
            "title": "Nice shop!",
            "body": "Upgrade to Shoppa Premium for ad-free shopping and unlimited lists.",
            "cta_text": "Go ad-free",
            "cta_url": "https://app.shoppa.app/subscriptions",
            "surface": AdSurface.CHECKOUT,
            "ad_format": AdFormat.INTERSTITIAL,
            "sort_order": 0,
        },
        {
            "slug": "session-rewarded",
            "title": "Bonus savings tip",
            "body": "Compare your next trip across four major retailers to find the best basket total.",
            "cta_text": "Open Compare",
            "cta_url": "https://app.shoppa.app/compare",
            "surface": AdSurface.CHECKOUT,
            "ad_format": AdFormat.REWARDED,
            "sort_order": 1,
        },
    ]
    for entry in launch:
        AdPlacement.objects.update_or_create(
            slug=entry["slug"],
            defaults={
                "title": entry["title"],
                "body": entry["body"],
                "cta_text": entry["cta_text"],
                "cta_url": entry["cta_url"],
                "surface": entry["surface"],
                "ad_format": entry["ad_format"],
                "sponsor_name": entry.get("sponsor_name", ""),
                "is_active": True,
                "sort_order": entry["sort_order"],
            },
        )


def _session_cap_reached(user, ad_format: str, session_key: str) -> bool:
    if ad_format not in FREQUENCY_CAPPED_FORMATS or not session_key:
        return False
    count = AdImpression.objects.filter(
        user=user,
        ad_format=ad_format,
        session_key=session_key,
    ).count()
    return count >= SESSION_CAP_PER_FORMAT


def get_placements(
    user,
    *,
    surface: str,
    ad_format: str | None = None,
    session_key: str = "",
):
    if not user_sees_ads(user):
        return []

    ensure_house_ads_seeded()
    queryset = AdPlacement.objects.filter(is_active=True, surface=surface)
    if ad_format:
        queryset = queryset.filter(ad_format=ad_format)

    placements = []
    for placement in queryset:
        if _session_cap_reached(user, placement.ad_format, session_key):
            continue
        placements.append(placement)
    return placements


def record_impression(
    user,
    placement: AdPlacement,
    *,
    surface: str,
    ad_format: str,
    session_key: str = "",
):
    if not user_sees_ads(user):
        return None
    if _session_cap_reached(user, ad_format, session_key):
        return None
    return AdImpression.objects.create(
        user=user,
        placement=placement,
        surface=surface,
        ad_format=ad_format,
        session_key=session_key or "",
    )


def record_click(user, placement: AdPlacement):
    if not user_sees_ads(user):
        return None
    return AdClick.objects.create(user=user, placement=placement)


def placement_payload(placement: AdPlacement) -> dict:
    return {
        "id": str(placement.id),
        "slug": placement.slug,
        "title": placement.title,
        "body": placement.body,
        "cta_text": placement.cta_text,
        "cta_url": placement.cta_url,
        "surface": placement.surface,
        "ad_format": placement.ad_format,
        "sponsor_name": placement.sponsor_name or None,
    }
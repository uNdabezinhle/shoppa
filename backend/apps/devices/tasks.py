"""FCM dispatch for price-drop alerts (M8)."""
from __future__ import annotations

import json
import logging
import urllib.error
import urllib.request

from celery import shared_task
from django.conf import settings

logger = logging.getLogger(__name__)


@shared_task(name="devices.send_fcm_price_drop")
def send_fcm_price_drop(user_ids, title, body, payload=None):
    """Send FCM notification to all registered devices for *user_ids*.

    No-ops when FCM_SERVER_KEY is empty (local/CI). Returns a summary dict.
    """
    payload = payload or {}
    if not settings.FCM_SERVER_KEY:
        return {"sent": 0, "skipped": "no_fcm_key"}

    from .models import Device

    tokens = list(
        Device.objects.filter(user_id__in=user_ids)
        .values_list("token", flat=True)
        .distinct()
    )
    if not tokens:
        return {"sent": 0, "skipped": "no_devices"}

    sent = 0
    errors = 0
    for token in tokens:
        ok = _send_legacy_fcm(token, title, body, payload)
        if ok:
            sent += 1
        else:
            errors += 1
    return {"sent": sent, "errors": errors, "tokens": len(tokens)}


def _send_legacy_fcm(token: str, title: str, body: str, data: dict) -> bool:
    """FCM HTTP legacy API — works with a server key string."""
    message = {
        "to": token,
        "notification": {"title": title, "body": body},
        "data": {k: str(v) for k, v in data.items()},
        "priority": "high",
    }
    req = urllib.request.Request(
        "https://fcm.googleapis.com/fcm/send",
        data=json.dumps(message).encode("utf-8"),
        headers={
            "Authorization": f"key={settings.FCM_SERVER_KEY}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return 200 <= resp.status < 300
    except urllib.error.HTTPError as exc:
        logger.warning("FCM HTTP error for token …%s: %s", token[-8:], exc.code)
        return False
    except Exception as exc:  # noqa: BLE001
        logger.warning("FCM send failed: %s", exc)
        return False

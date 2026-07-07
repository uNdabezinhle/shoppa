#!/usr/bin/env python
"""M7 launch gate smoke — platform readiness + full milestone regression.

Usage (from backend/):
    python scripts/m7_smoke.py
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "shoppa_api.settings")
_hosts = os.environ.get("ALLOWED_HOSTS", "localhost,127.0.0.1")
if "testserver" not in _hosts:
    os.environ["ALLOWED_HOSTS"] = f"{_hosts},testserver"

import django  # noqa: E402

django.setup()

from django.urls import reverse  # noqa: E402
from rest_framework.test import APIClient  # noqa: E402

from apps.users.models import User  # noqa: E402


def _run_script(name: str) -> int:
    script = BACKEND_DIR / "scripts" / name
    result = subprocess.run(
        [sys.executable, str(script)],
        cwd=str(BACKEND_DIR),
        env=os.environ.copy(),
    )
    return result.returncode


def main() -> int:
    client = APIClient()

    live = client.get(reverse("health"))
    if live.status_code != 200:
        print("FAIL: liveness probe failed", file=sys.stderr)
        return 1

    ready = client.get(reverse("health-ready"))
    ready_payload = getattr(ready, "data", None) or ready.json()
    if ready.status_code != 200 or ready_payload.get("status") != "ready":
        print("FAIL: readiness probe failed", file=sys.stderr)
        return 1

    meta = client.get(reverse("meta-launch"))
    if meta.status_code != 200 or not meta.data.get("launch_ready"):
        print("FAIL: launch meta not ready", file=sys.stderr)
        return 1
    if len(meta.data.get("milestones_complete", [])) < 6:
        print("FAIL: expected six completed milestones", file=sys.stderr)
        return 1

    user, _ = User.objects.get_or_create(
        username="m7-privacy@example.com",
        defaults={"email": "m7-privacy@example.com", "region": "ZA"},
    )
    user.set_password("smoke-test-pass!")
    user.save()
    client.force_authenticate(user)

    export = client.get(reverse("users-data-export"))
    if export.status_code != 200 or export.data.get("user", {}).get("email") != user.email:
        print("FAIL: POPIA data export failed", file=sys.stderr)
        return 1

    for script in ("m3_smoke.py", "m4_smoke.py", "m5_smoke.py", "m6_smoke.py"):
        code = _run_script(script)
        if code != 0:
            print(f"FAIL: {script} returned {code}", file=sys.stderr)
            return 1

    print(
        "M7 launch smoke OK: health + ready + meta + privacy export + "
        "m3–m6 regression"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
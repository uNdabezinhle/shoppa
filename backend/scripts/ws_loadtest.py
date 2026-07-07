#!/usr/bin/env python
"""Staging WebSocket load probe for the M2 gate.

Opens N concurrent ws /lists/{id} connections, fires a channel-layer
broadcast, and reports how long fan-out took. Requires Daphne/ASGI stack
and optionally REDIS_URL for multi-worker fan-out.

Usage (from backend/):
    python scripts/ws_loadtest.py --subscribers 50 --list-id <uuid>

Environment:
    DJANGO_SETTINGS_MODULE=shoppa_api.settings
    DATABASE_URL, SECRET_KEY — same as the API process.
    REDIS_URL — recommended on staging (matches production channel layer).
"""
from __future__ import annotations

import argparse
import asyncio
import os
import sys
import time
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "shoppa_api.settings")

import django  # noqa: E402

django.setup()

from channels.layers import get_channel_layer  # noqa: E402
from channels.routing import URLRouter  # noqa: E402
from channels.testing import WebsocketCommunicator  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from apps.lists.middleware import JWTAuthMiddlewareStack  # noqa: E402
from apps.lists.models import ShoppingList  # noqa: E402
from apps.lists.routing import websocket_urlpatterns  # noqa: E402
from apps.users.models import User  # noqa: E402

_application = JWTAuthMiddlewareStack(URLRouter(websocket_urlpatterns))


async def _drain(communicator: WebsocketCommunicator, seconds: float = 0.2) -> None:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            await asyncio.wait_for(communicator.receive_json_from(), timeout=0.05)
        except asyncio.TimeoutError:
            break


async def run_probe(list_id: str, subscribers: int, deadline: float) -> int:
    list_obj = ShoppingList.objects.select_related("owner").get(pk=list_id)
    token = str(RefreshToken.for_user(list_obj.owner).access_token)
    path = f"/ws/lists/{list_id}/?token={token}"

    communicators = [
        WebsocketCommunicator(_application, path) for _ in range(subscribers)
    ]
    for comm in communicators:
        connected, _ = await comm.connect()
        if not connected:
            raise RuntimeError("WebSocket connection rejected")
        await _drain(comm)

    channel_layer = get_channel_layer()
    started = time.monotonic()
    await channel_layer.group_send(
        f"list_{list_id}",
        {
            "type": "list.event",
            "event": "item.added",
            "payload": {"id": "load-probe", "name": "Load probe"},
        },
    )

    received = 0
    for comm in communicators:
        await asyncio.wait_for(comm.receive_json_from(), timeout=deadline)
        received += 1

    elapsed_ms = int((time.monotonic() - started) * 1000)
    for comm in communicators:
        await comm.disconnect()

    print(
        f"Fan-out OK: {received}/{subscribers} subscribers "
        f"in {elapsed_ms} ms (deadline {int(deadline * 1000)} ms)"
    )
    return elapsed_ms


def main() -> None:
    parser = argparse.ArgumentParser(description="Shoppa WebSocket load probe")
    parser.add_argument("--list-id", required=True, help="Shopping list UUID")
    parser.add_argument("--subscribers", type=int, default=50)
    parser.add_argument("--deadline", type=float, default=2.0)
    args = parser.parse_args()

    if not User.objects.exists():
        print("No users in database — run seed_launch_data first.", file=sys.stderr)
        sys.exit(1)

    elapsed_ms = asyncio.run(
        run_probe(args.list_id, args.subscribers, args.deadline)
    )
    if elapsed_ms > int(args.deadline * 1000):
        sys.exit(2)


if __name__ == "__main__":
    main()
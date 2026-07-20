"""Tracks live WebSocket presence per list (M2 / Implementation Plan §6.2).

When a collaborator opens a list, other subscribers see a
``presence.joined`` event; disconnect emits ``presence.left``. Counts
are per user so multiple tabs from the same account only emit one join
and one leave.

With REDIS_URL set, session counts live in Django's cache (Redis) so
multiple workers/processes share presence. Without Redis, falls back to
process-local memory (fine for CI and single-process dev).
"""
import threading

from django.conf import settings

from .realtime import broadcast_list_event

_lock = threading.Lock()
# list_id -> {user_id: connection_count}  (in-process fallback only)
_sessions: dict[str, dict[str, int]] = {}

_CACHE_PREFIX = "shoppa:list_presence:"
_CACHE_TTL = 60 * 60 * 6  # 6h safety; live sockets refresh counts on join/leave


def _use_shared_cache() -> bool:
    return bool(getattr(settings, "REDIS_URL", None) or "")


def _cache_key(list_key: str) -> str:
    return f"{_CACHE_PREFIX}{list_key}"


def _load_users(list_key: str) -> dict[str, int]:
    if _use_shared_cache():
        from django.core.cache import cache

        data = cache.get(_cache_key(list_key))
        if isinstance(data, dict):
            return {str(k): int(v) for k, v in data.items()}
        return {}
    with _lock:
        return dict(_sessions.get(list_key, {}))


def _save_users(list_key: str, users: dict[str, int]) -> None:
    if _use_shared_cache():
        from django.core.cache import cache

        key = _cache_key(list_key)
        if users:
            cache.set(key, users, timeout=_CACHE_TTL)
        else:
            cache.delete(key)
        return
    with _lock:
        if users:
            _sessions[list_key] = users
        else:
            _sessions.pop(list_key, None)


def _initials(email: str) -> str:
    local = email.split("@")[0]
    parts = local.replace(".", " ").replace("_", " ").split()
    if len(parts) >= 2:
        return (parts[0][0] + parts[1][0]).upper()
    return local[:2].upper() if local else "?"


def _presence_payload(user) -> dict:
    return {
        "user_id": str(user.id),
        "email": user.email,
        "initials": _initials(user.email),
    }


def user_joined(list_id, user) -> None:
    user_id = str(user.id)
    list_key = str(list_id)
    users = _load_users(list_key)
    count = users.get(user_id, 0) + 1
    users[user_id] = count
    _save_users(list_key, users)
    if count == 1:
        broadcast_list_event(list_id, "presence.joined", _presence_payload(user))


def user_left(list_id, user) -> None:
    user_id = str(user.id)
    list_key = str(list_id)
    users = _load_users(list_key)
    count = users.get(user_id, 0) - 1
    if count <= 0:
        users.pop(user_id, None)
        is_gone = True
    else:
        users[user_id] = count
        is_gone = False
    _save_users(list_key, users)
    if is_gone:
        broadcast_list_event(list_id, "presence.left", {"user_id": user_id})


def active_users(list_id) -> list[dict]:
    """Returns presence payloads for users with at least one live socket."""
    list_key = str(list_id)
    users = _load_users(list_key)
    user_ids = list(users.keys())
    if not user_ids:
        return []
    from django.contrib.auth import get_user_model

    user_model = get_user_model()
    db_users = user_model.objects.filter(pk__in=user_ids)
    by_id = {str(u.id): u for u in db_users}
    return [
        _presence_payload(by_id[uid])
        for uid in user_ids
        if uid in by_id
    ]


def email_initials(email: str) -> str:
    return _initials(email)

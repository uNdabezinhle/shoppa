"""Tracks live WebSocket presence per list (M2 / Implementation Plan §6.2).

When a collaborator opens a list, other subscribers see a
``presence.joined`` event; disconnect emits ``presence.left``. Counts
are per user so multiple tabs from the same account only emit one join
and one leave.
"""
import threading

from .realtime import broadcast_list_event

_lock = threading.Lock()
# list_id -> {user_id: connection_count}
_sessions: dict[str, dict[str, int]] = {}


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
    is_new = False
    with _lock:
        users = _sessions.setdefault(list_key, {})
        count = users.get(user_id, 0) + 1
        users[user_id] = count
        is_new = count == 1
    if is_new:
        broadcast_list_event(list_id, "presence.joined", _presence_payload(user))


def user_left(list_id, user) -> None:
    user_id = str(user.id)
    list_key = str(list_id)
    is_gone = False
    with _lock:
        users = _sessions.get(list_key, {})
        count = users.get(user_id, 0) - 1
        if count <= 0:
            users.pop(user_id, None)
            if not users:
                _sessions.pop(list_key, None)
            is_gone = True
        else:
            users[user_id] = count
    if is_gone:
        broadcast_list_event(list_id, "presence.left", {"user_id": user_id})


def active_users(list_id) -> list[dict]:
    """Returns presence payloads for users with at least one live socket."""
    list_key = str(list_id)
    with _lock:
        user_ids = list(_sessions.get(list_key, {}).keys())
    if not user_ids:
        return []
    from django.contrib.auth import get_user_model

    user_model = get_user_model()
    users = user_model.objects.filter(pk__in=user_ids)
    by_id = {str(u.id): u for u in users}
    return [
        _presence_payload(by_id[uid])
        for uid in user_ids
        if uid in by_id
    ]


def email_initials(email: str) -> str:
    return _initials(email)
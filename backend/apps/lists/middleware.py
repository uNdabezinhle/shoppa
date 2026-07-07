"""ASGI auth middleware for the real-time list channel (SRS FR-3.2).

Browser/mobile WebSocket handshakes can't carry an Authorization header,
so clients authenticate the same JWT access token used for REST calls via
a query string parameter instead:

    ws://.../ws/lists/{id}/?token=<access-token>

This mirrors djangorestframework-simplejwt's access-token validation
(same secret, same "user_id" claim) without depending on DRF's
request/response cycle, which doesn't apply to ASGI WebSocket scopes.
"""
from channels.db import database_sync_to_async
from channels.middleware import BaseMiddleware
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import AccessToken


@database_sync_to_async
def _user_from_token(token):
    from django.contrib.auth import get_user_model
    from django.contrib.auth.models import AnonymousUser

    user_model = get_user_model()
    try:
        validated = AccessToken(token)
        return user_model.objects.get(pk=validated["user_id"])
    except (TokenError, user_model.DoesNotExist, KeyError):
        return AnonymousUser()


class JWTAuthMiddleware(BaseMiddleware):
    async def __call__(self, scope, receive, send):
        from django.contrib.auth.models import AnonymousUser
        from urllib.parse import parse_qs

        query_string = scope.get("query_string", b"").decode()
        token = parse_qs(query_string).get("token", [None])[0]
        scope["user"] = await _user_from_token(token) if token else AnonymousUser()
        return await super().__call__(scope, receive, send)


def JWTAuthMiddlewareStack(inner):
    return JWTAuthMiddleware(inner)

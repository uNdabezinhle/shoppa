import os

from django.core.asgi import get_asgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "shoppa_api.settings")

# Must be created before importing anything that touches models/apps
# (Channels' own docs convention), since it triggers Django's app registry
# to finish loading.
django_asgi_app = get_asgi_application()

from channels.routing import ProtocolTypeRouter, URLRouter  # noqa: E402

from apps.chat.routing import websocket_urlpatterns as chat_ws_urls  # noqa: E402
from apps.delivery.routing import websocket_urlpatterns as delivery_ws_urls  # noqa: E402
from apps.lists.middleware import JWTAuthMiddlewareStack  # noqa: E402
from apps.lists.routing import websocket_urlpatterns as list_ws_urls  # noqa: E402

application = ProtocolTypeRouter(
    {
        "http": django_asgi_app,
        # SRS FR-3.2 / FR-3.4 / API Specification §9: ws /lists/{id},
        # ws /lists/{id}/chat, ws /lists/{id}/delivery. Clients authenticate
        # with the same JWT access token used for REST (query string param).
        "websocket": JWTAuthMiddlewareStack(
            URLRouter(list_ws_urls + chat_ws_urls + delivery_ws_urls)
        ),
    }
)

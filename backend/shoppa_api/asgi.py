import os

from django.core.asgi import get_asgi_application

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "shoppa_api.settings")

# Must be created before importing anything that touches models/apps
# (Channels' own docs convention), since it triggers Django's app registry
# to finish loading.
django_asgi_app = get_asgi_application()

from channels.routing import ProtocolTypeRouter, URLRouter  # noqa: E402

from apps.lists.middleware import JWTAuthMiddlewareStack  # noqa: E402
from apps.lists.routing import websocket_urlpatterns  # noqa: E402

application = ProtocolTypeRouter(
    {
        "http": django_asgi_app,
        # SRS FR-3.2 / API Specification §9: ws /lists/{id}. Mobile/web
        # clients authenticate with the same JWT access token used for
        # REST calls, passed as a query string param (see middleware.py).
        "websocket": JWTAuthMiddlewareStack(URLRouter(websocket_urlpatterns)),
    }
)

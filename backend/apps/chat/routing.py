from django.urls import re_path

from .consumers import ChatConsumer

websocket_urlpatterns = [
    re_path(
        r"^ws/lists/(?P<list_id>[0-9a-fA-F-]{36})/chat/$",
        ChatConsumer.as_asgi(),
    ),
]
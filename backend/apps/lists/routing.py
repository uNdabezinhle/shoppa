from django.urls import re_path

from .consumers import ListConsumer

websocket_urlpatterns = [
    re_path(r"^ws/lists/(?P<list_id>[0-9a-fA-F-]{36})/$", ListConsumer.as_asgi()),
]

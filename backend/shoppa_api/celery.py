"""Celery application (Implementation Plan §3: async workers + Beat).

Broker and result backend share REDIS_URL with Channels. When Redis is
unavailable (local sqlite dev, CI) tasks run eagerly in-process.
"""
import os

from celery import Celery

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "shoppa_api.settings")

app = Celery("shoppa_api")
app.config_from_object("django.conf:settings", namespace="CELERY")
app.autodiscover_tasks()
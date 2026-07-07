"""Shared Celery tasks. Domain-specific tasks live in their apps later."""
from celery import shared_task


@shared_task(name="shoppa.ping")
def ping():
    """Health-check task used to verify the worker boots."""
    return "pong"
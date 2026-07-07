"""API rate limits (Implementation Plan §7.2)."""
from rest_framework.throttling import AnonRateThrottle, UserRateThrottle


class AuthRateThrottle(AnonRateThrottle):
    scope = "auth"


class ReadRateThrottle(UserRateThrottle):
    scope = "reads"
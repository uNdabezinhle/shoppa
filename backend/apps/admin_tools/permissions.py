"""Admin-only API access (BRD account-type: Admin)."""
from rest_framework import permissions

from apps.users.models import AccountType


class IsAdminUser(permissions.BasePermission):
    def has_permission(self, request, view):
        user = request.user
        return (
            user.is_authenticated
            and user.account_type == AccountType.ADMIN
        )
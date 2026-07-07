"""POPIA data subject endpoints."""
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from .privacy import build_user_data_export, delete_user_account


class DataExportView(APIView):
    """GET /v1/users/me/data-export — portable copy of the caller's data."""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        return Response(build_user_data_export(request.user))


class AccountDeleteView(APIView):
    """POST /v1/users/me/delete-account — erasure with password confirmation."""

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        password = request.data.get("password", "")
        if not password:
            return Response(
                {
                    "error": {
                        "code": "validation_error",
                        "message": "password is required to delete your account.",
                    }
                },
                status=status.HTTP_422_UNPROCESSABLE_ENTITY,
            )
        try:
            delete_user_account(request.user, password=password)
        except ValueError:
            return Response(
                {
                    "error": {
                        "code": "unauthorized",
                        "message": "Password is incorrect.",
                    }
                },
                status=status.HTTP_401_UNAUTHORIZED,
            )
        return Response({"status": "deleted"})
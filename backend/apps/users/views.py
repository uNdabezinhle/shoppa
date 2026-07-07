"""Accounts & Authentication views (SRS §3.1).

RegisterView: FR-1.1 (email/password registration), FR-1.2 (account
types), FR-1.4 (region association). MeView proves the JWT chain works
end-to-end from the mobile client (used by the Flutter home screen after
login).
"""
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from shoppa_api.throttling import AuthRateThrottle

from .models import AccountType, User
from .serializers import (
    PasswordResetRequestSerializer,
    RegisterSerializer,
    UserSerializer,
    UserUpdateSerializer,
)


class RegisterView(generics.CreateAPIView):
    queryset = User.objects.all()
    serializer_class = RegisterSerializer
    permission_classes = [permissions.AllowAny]
    throttle_classes = [AuthRateThrottle]

    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        return Response(UserSerializer(user).data, status=201)


class MeView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        return Response(UserSerializer(request.user).data)

    def patch(self, request):
        serializer = UserUpdateSerializer(
            request.user, data=request.data, partial=True
        )
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(UserSerializer(request.user).data)


class PasswordResetView(APIView):
    """POST /auth/password-reset — stub that always returns 202 (FR-1.3).

    Does not reveal whether the email exists; full email delivery lands
    in a later phase once the notifications app is live.
    """

    permission_classes = [permissions.AllowAny]
    throttle_classes = [AuthRateThrottle]

    def post(self, request):
        serializer = PasswordResetRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        return Response(
            {"detail": "If that email exists, a reset link has been sent."},
            status=status.HTTP_202_ACCEPTED,
        )


class UpgradeToProfessionalView(APIView):
    """POST /users/me/upgrade — FR-1.5 Personal → Professional."""

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        user = request.user
        if user.account_type != AccountType.PERSONAL:
            return Response(
                {
                    "error": {
                        "code": "validation_error",
                        "message": "Only personal accounts can upgrade.",
                    }
                },
                status=status.HTTP_422_UNPROCESSABLE_ENTITY,
            )
        user.account_type = AccountType.PROFESSIONAL
        user.save(update_fields=["account_type"])
        return Response(UserSerializer(user).data)
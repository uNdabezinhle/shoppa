"""Device registration for FCM push (M8)."""
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import Device
from .serializers import DeviceSerializer


class DeviceRegisterView(APIView):
    """POST /v1/devices — register or refresh a push token for the user."""

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        serializer = DeviceSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        token = serializer.validated_data["token"]
        platform = serializer.validated_data["platform"]
        device, _created = Device.objects.update_or_create(
            user=request.user,
            token=token,
            defaults={"platform": platform},
        )
        return Response(
            DeviceSerializer(device).data,
            status=status.HTTP_201_CREATED,
        )

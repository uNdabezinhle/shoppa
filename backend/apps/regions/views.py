from rest_framework import generics, permissions

from .models import Region
from .serializers import RegionSerializer


class RegionListView(generics.ListAPIView):
    queryset = Region.objects.all()
    serializer_class = RegionSerializer
    permission_classes = [permissions.AllowAny]
    pagination_class = None


class RegionDetailView(generics.RetrieveAPIView):
    queryset = Region.objects.all()
    serializer_class = RegionSerializer
    permission_classes = [permissions.AllowAny]
    lookup_field = "code"
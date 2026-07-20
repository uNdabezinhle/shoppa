from django.urls import path

from .views import DeviceRegisterView

urlpatterns = [
    path("devices", DeviceRegisterView.as_view(), name="devices-register"),
]

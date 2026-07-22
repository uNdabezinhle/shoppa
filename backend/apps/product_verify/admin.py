from django.contrib import admin

from .models import GtinProduct, ProductCorrection, ScanEvent, UserAllergenProfile


@admin.register(GtinProduct)
class GtinProductAdmin(admin.ModelAdmin):
    list_display = ("gtin", "name", "brand", "found", "source", "fetched_at")
    search_fields = ("gtin", "name", "brand")
    list_filter = ("found", "source", "region")


@admin.register(UserAllergenProfile)
class UserAllergenProfileAdmin(admin.ModelAdmin):
    list_display = ("user", "consent_at", "updated_at")
    search_fields = ("user__email",)


@admin.register(ProductCorrection)
class ProductCorrectionAdmin(admin.ModelAdmin):
    list_display = ("gtin", "field", "status", "user", "created_at")
    list_filter = ("status", "field")


@admin.register(ScanEvent)
class ScanEventAdmin(admin.ModelAdmin):
    list_display = ("gtin", "product_name", "level", "user", "scanned_at")
    list_filter = ("level",)

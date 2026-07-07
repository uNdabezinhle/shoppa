from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as DjangoUserAdmin

from .models import User


@admin.register(User)
class UserAdmin(DjangoUserAdmin):
    model = User
    list_display = ("email", "account_type", "region", "is_staff", "created_at")
    ordering = ("-created_at",)
    fieldsets = DjangoUserAdmin.fieldsets + (
        ("Shoppa", {"fields": ("account_type", "region", "locale")}),
    )

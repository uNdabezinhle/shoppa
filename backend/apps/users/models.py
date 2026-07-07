"""Users & Auth (Solution Architecture §4: `users` app).

Covers SRS FR-1.1 (email/password registration), FR-1.2 (four account
types), FR-1.4 (region/locale association). IDs are UUIDs per the API
Specification's resource-ID convention.
"""
import uuid

from django.contrib.auth.models import AbstractUser
from django.db import models


class AccountType(models.TextChoices):
    PERSONAL = "personal", "Personal"
    PROFESSIONAL = "professional", "Professional"
    STORE = "store", "Store / Brand"
    ADMIN = "admin", "Admin"


class User(AbstractUser):
    """Custom user model — email is the login identifier; username is kept
    (auto-derived from email) only because Django's auth machinery expects it.
    """

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    email = models.EmailField(unique=True)
    account_type = models.CharField(
        max_length=20, choices=AccountType.choices, default=AccountType.PERSONAL
    )
    region = models.CharField(max_length=8, default="ZA")
    locale = models.CharField(max_length=8, default="en-ZA")
    # Price Intelligence (SRS FR-5.2, API Specification Definitions §1.3:
    # "a per-user rating reflecting reliability of contributed data").
    # 0.0-1.0; new users start at a moderate default and (eventually) move
    # as their crowd-sourced price submissions are corroborated or
    # contradicted by other sources -- that adjustment logic is a later
    # follow-up, this just adds the field the reconciliation weighting
    # already depends on.
    trust_score = models.FloatField(default=0.5)
    created_at = models.DateTimeField(auto_now_add=True)

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS = ["username"]

    def __str__(self):
        return self.email

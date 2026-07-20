# Generated manually for pending list invites (unregistered emails).

import uuid

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ("lists", "0006_alter_listactivity_action_list_meta"),
    ]

    operations = [
        migrations.CreateModel(
            name="ListInvite",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid4,
                        editable=False,
                        primary_key=True,
                        serialize=False,
                    ),
                ),
                ("email", models.EmailField(db_index=True, max_length=254)),
                (
                    "permission",
                    models.CharField(
                        choices=[("view", "View"), ("edit", "Edit")],
                        default="view",
                        max_length=10,
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                (
                    "invited_by",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="list_invites_sent",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "list",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="invites",
                        to="lists.shoppinglist",
                    ),
                ),
            ],
            options={
                "ordering": ["-created_at"],
            },
        ),
        migrations.AddConstraint(
            model_name="listinvite",
            constraint=models.UniqueConstraint(
                fields=("list", "email"), name="unique_list_invite_email"
            ),
        ),
    ]

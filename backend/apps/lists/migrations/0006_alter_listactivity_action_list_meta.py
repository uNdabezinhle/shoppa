# Generated manually for list create/rename/publish activity actions.

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("lists", "0005_shoppinglist_event_date_shoppinglist_event_name_and_more"),
    ]

    operations = [
        migrations.AlterField(
            model_name="listactivity",
            name="action",
            field=models.CharField(
                choices=[
                    ("item_added", "Item added"),
                    ("item_updated", "Item updated"),
                    ("item_checked", "Item checked"),
                    ("item_removed", "Item removed"),
                    ("collaborator_joined", "Collaborator joined"),
                    ("collaborator_removed", "Collaborator removed"),
                    ("list_scaled", "List scaled"),
                    ("list_created", "List created"),
                    ("list_updated", "List updated"),
                    ("list_published", "List published"),
                    ("list_unpublished", "List unpublished"),
                ],
                max_length=30,
            ),
        ),
    ]

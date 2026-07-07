from django.db import migrations, models


class Migration(migrations.Migration):
    initial = True

    dependencies = []

    operations = [
        migrations.CreateModel(
            name="Region",
            fields=[
                ("code", models.CharField(max_length=8, primary_key=True, serialize=False)),
                ("name", models.CharField(max_length=100)),
                ("currency_code", models.CharField(max_length=3)),
                ("locale", models.CharField(max_length=8)),
                (
                    "tax_rate",
                    models.DecimalField(
                        decimal_places=4,
                        default=0,
                        help_text="VAT as a fraction, e.g. 0.15",
                        max_digits=5,
                    ),
                ),
            ],
            options={"ordering": ["code"]},
        ),
    ]
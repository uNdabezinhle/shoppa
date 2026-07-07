"""Region configuration (Architecture §5.1, SRS FR-1.4)."""
from django.db import models


class Region(models.Model):
    code = models.CharField(max_length=8, primary_key=True)
    name = models.CharField(max_length=100)
    currency_code = models.CharField(max_length=3)
    locale = models.CharField(max_length=8)
    tax_rate = models.DecimalField(
        max_digits=5, decimal_places=4, default=0, help_text="VAT as a fraction, e.g. 0.15"
    )

    class Meta:
        ordering = ["code"]

    def __str__(self):
        return self.code
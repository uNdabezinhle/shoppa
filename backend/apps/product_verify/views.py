"""Product verification API views."""
from django.utils import timezone
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.throttling import UserRateThrottle
from rest_framework.views import APIView

from .allergens import CANONICAL_ALLERGENS
from .gtin import normalize_gtin
from .models import ProductCorrection, ScanEvent, UserAllergenProfile
from .serializers import (
    ProductCorrectionSerializer,
    canonical_allergen_list,
)
from .services import verify_gtin


class VerifyThrottle(UserRateThrottle):
    rate = "60/min"


class RefreshThrottle(UserRateThrottle):
    rate = "10/min"


class ProductVerifyView(APIView):
    """GET /v1/products/verify?gtin= — barcode lookup + personalised scoring."""

    permission_classes = [permissions.IsAuthenticated]
    throttle_classes = [VerifyThrottle]

    def get(self, request):
        raw = request.query_params.get("gtin", "")
        try:
            payload = verify_gtin(raw, user=request.user, force_refresh=False)
        except Exception:
            return Response(
                {
                    "error": {
                        "code": "upstream_unavailable",
                        "message": (
                            "Product database temporarily unavailable. "
                            "Try again or use a previously cached scan offline."
                        ),
                    }
                },
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
        if payload.get("status") == "invalid":
            return Response(payload, status=status.HTTP_400_BAD_REQUEST)
        return Response(payload)


class ProductVerifyRefreshView(APIView):
    """POST /v1/products/verify/refresh — force re-fetch from OFF."""

    permission_classes = [permissions.IsAuthenticated]
    throttle_classes = [RefreshThrottle]

    def post(self, request):
        raw = request.data.get("gtin", "")
        try:
            payload = verify_gtin(
                raw, user=request.user, force_refresh=True
            )
        except Exception:
            return Response(
                {
                    "error": {
                        "code": "upstream_unavailable",
                        "message": "Could not refresh product data.",
                    }
                },
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
        if payload.get("status") == "invalid":
            return Response(payload, status=status.HTTP_400_BAD_REQUEST)
        return Response(payload)


class ProductByGtinView(APIView):
    """GET /v1/products/by-gtin/{gtin} — card without recording scan history."""

    permission_classes = [permissions.IsAuthenticated]
    throttle_classes = [VerifyThrottle]

    def get(self, request, gtin):
        try:
            payload = verify_gtin(
                gtin, user=request.user, force_refresh=False, record_scan=False
            )
        except Exception:
            return Response(
                {
                    "error": {
                        "code": "upstream_unavailable",
                        "message": "Product database temporarily unavailable.",
                    }
                },
                status=status.HTTP_503_SERVICE_UNAVAILABLE,
            )
        if payload.get("status") == "invalid":
            return Response(payload, status=status.HTTP_400_BAD_REQUEST)
        return Response(payload)


class AllergenProfileView(APIView):
    """GET/PUT /v1/users/me/allergen-profile"""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        try:
            profile = request.user.allergen_profile
        except UserAllergenProfile.DoesNotExist:
            return Response(
                {
                    "allergens": [],
                    "consent_at": None,
                    "updated_at": None,
                    "canonical": canonical_allergen_list(),
                }
            )
        return Response(
            {
                "allergens": profile.allergens or [],
                "consent_at": (
                    profile.consent_at.isoformat().replace("+00:00", "Z")
                    if profile.consent_at
                    else None
                ),
                "updated_at": profile.updated_at.isoformat().replace(
                    "+00:00", "Z"
                ),
                "canonical": canonical_allergen_list(),
            }
        )

    def put(self, request):
        from .allergens import normalize_allergen_list

        consent = request.data.get("consent")
        raw_allergens = request.data.get("allergens", [])
        if not isinstance(raw_allergens, list):
            return Response(
                {
                    "error": {
                        "code": "validation_error",
                        "message": "allergens must be a list of codes.",
                    }
                },
                status=status.HTTP_400_BAD_REQUEST,
            )
        allergens = normalize_allergen_list(raw_allergens)
        unknown = [
            a
            for a in raw_allergens
            if isinstance(a, str)
            and a not in CANONICAL_ALLERGENS
            and a not in allergens
        ]
        # Unknown tags are dropped by normalize; fine for MVP.

        try:
            profile = request.user.allergen_profile
            created = False
        except UserAllergenProfile.DoesNotExist:
            profile = None
            created = True

        if created or profile is None:
            if consent is not True:
                return Response(
                    {
                        "error": {
                            "code": "consent_required",
                            "message": (
                                "Consent is required to store allergen "
                                "preferences (health data under POPIA)."
                            ),
                        }
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )
            profile = UserAllergenProfile.objects.create(
                user=request.user,
                allergens=allergens,
                consent_at=timezone.now(),
            )
        else:
            profile.allergens = allergens
            if consent is True and profile.consent_at is None:
                profile.consent_at = timezone.now()
            profile.save()

        return Response(
            {
                "allergens": profile.allergens or [],
                "consent_at": (
                    profile.consent_at.isoformat().replace("+00:00", "Z")
                    if profile.consent_at
                    else None
                ),
                "updated_at": profile.updated_at.isoformat().replace(
                    "+00:00", "Z"
                ),
                "canonical": canonical_allergen_list(),
            }
        )


class ScanHistoryView(APIView):
    """GET /v1/users/me/scan-history"""

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        limit = min(int(request.query_params.get("limit", 50)), 100)
        events = ScanEvent.objects.filter(user=request.user)[:limit]
        return Response(
            {
                "results": [
                    {
                        "id": str(e.id),
                        "gtin": e.gtin,
                        "level": e.level,
                        "product_name": e.product_name,
                        "scanned_at": e.scanned_at.isoformat().replace(
                            "+00:00", "Z"
                        ),
                    }
                    for e in events
                ]
            }
        )


class ProductCorrectionView(APIView):
    """POST /v1/products/corrections"""

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        data = request.data.copy() if hasattr(request.data, "copy") else dict(request.data)
        gtin = normalize_gtin(str(data.get("gtin", "")))
        if not gtin:
            return Response(
                {
                    "error": {
                        "code": "invalid_gtin",
                        "message": "A valid gtin is required.",
                    }
                },
                status=status.HTTP_400_BAD_REQUEST,
            )
        data["gtin"] = gtin
        ser = ProductCorrectionSerializer(data=data)
        if not ser.is_valid():
            return Response(
                {
                    "error": {
                        "code": "validation_error",
                        "message": "Invalid correction.",
                        "fields": ser.errors,
                    }
                },
                status=status.HTTP_400_BAD_REQUEST,
            )
        obj = ProductCorrection.objects.create(
            user=request.user,
            gtin=ser.validated_data["gtin"],
            field=ser.validated_data["field"],
            suggested_value=ser.validated_data.get("suggested_value", ""),
            note=ser.validated_data.get("note", ""),
        )
        return Response(
            ProductCorrectionSerializer(obj).data,
            status=status.HTTP_201_CREATED,
        )

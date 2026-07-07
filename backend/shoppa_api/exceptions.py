"""Shared DRF exception handler producing the API Specification's error envelope.

See API Specification §5 (Error Handling): every error response returns
{"error": {"code": ..., "message": ..., "fields": {...}}} with per-field
detail for validation errors.
"""
from rest_framework.views import exception_handler as drf_exception_handler


def shoppa_exception_handler(exc, context):
    response = drf_exception_handler(exc, context)
    if response is None:
        return None

    detail = response.data

    fields = None
    if isinstance(detail, dict):
        message = "One or more fields are invalid." if response.status_code == 400 else "Request failed."
        # DRF puts field errors as {field: [messages]} for validation errors.
        non_field = detail.pop("detail", None)
        if detail:
            fields = detail
        if non_field:
            message = str(non_field)
    else:
        message = str(detail)

    code = {
        400: "validation_error",
        401: "unauthorized",
        403: "forbidden",
        404: "not_found",
        409: "conflict",
        422: "validation_error",
        429: "rate_limited",
    }.get(response.status_code, "error")

    error_body = {"code": code, "message": message}
    if fields:
        error_body["fields"] = fields

    response.data = {"error": error_body}
    return response

"""Cross-cutting request middleware (Architecture §12 observability)."""
import uuid

CORRELATION_HEADER = "X-Correlation-ID"


class CorrelationIdMiddleware:
    """Assigns a correlation ID to every request for log tracing."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        correlation_id = request.headers.get(CORRELATION_HEADER) or uuid.uuid4().hex
        request.correlation_id = correlation_id
        response = self.get_response(request)
        response[CorrelationIdMiddleware.header_name] = correlation_id
        return response

    header_name = CORRELATION_HEADER
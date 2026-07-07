# Shoppa backend — Django + DRF API (Solution Architecture §3, AD-7: Docker
# for consistent build/runtime packaging across all environments).
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends libpq-dev gcc \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .
RUN chmod +x /app/docker-entrypoint.sh

RUN adduser --disabled-password --no-create-home shoppa \
    && chown -R shoppa:shoppa /app
USER shoppa

EXPOSE 8000
# Daphne (not gunicorn+WSGI) so the same process serves both the REST API
# and the ws /lists/{id} real-time channel (Architecture AD-3: Django
# Channels for real-time). See shoppa_api/asgi.py for the ProtocolTypeRouter.
ENTRYPOINT ["/app/docker-entrypoint.sh"]
CMD ["daphne", "-b", "0.0.0.0", "-p", "8000", "shoppa_api.asgi:application"]
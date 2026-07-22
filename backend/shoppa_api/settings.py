"""
Django settings for shoppa_api.

Conventions follow the Shoppa API Specification: versioned API at /v1,
JSON everywhere, UUID resource IDs, money as integer minor units + currency
code, region-scoped data (Solution Architecture §2, §5.1).
"""
import os
from datetime import timedelta
from pathlib import Path

import dj_database_url
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")

SECRET_KEY = os.environ.get("SECRET_KEY", "insecure-dev-key-change-me")
DEBUG = os.environ.get("DEBUG", "True") == "True"
ALLOWED_HOSTS = os.environ.get("ALLOWED_HOSTS", "localhost,127.0.0.1").split(",")

INSTALLED_APPS = [
    # "daphne" first so `manage.py runserver` uses Channels' ASGI dev
    # server (which serves WebSockets too) instead of plain WSGI --
    # matches how the app actually runs in production (asgi.py + Daphne).
    "daphne",
    "shoppa_api.apps.ShoppaApiConfig",
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "rest_framework",
    "rest_framework_simplejwt",
    "corsheaders",
    "channels",
    "apps.users",
    "apps.lists",
    "apps.price_intelligence",
    "apps.promotions",
    "apps.regions",
    "apps.delivery",
    "apps.chat",
    "apps.notifications",
    "apps.subscriptions",
    "apps.admin_tools",
    "apps.ads",
    "apps.devices",
    "apps.product_verify",
    "django_celery_beat",
]

MIDDLEWARE = [
    "shoppa_api.middleware.CorrelationIdMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "shoppa_api.urls"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.debug",
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

WSGI_APPLICATION = "shoppa_api.wsgi.application"
ASGI_APPLICATION = "shoppa_api.asgi.application"

# SRS FR-3.2 / Architecture §8: Django Channels for real-time list
# collaboration. REDIS_URL (also used for Celery in later phases) selects
# the production channel layer; falling back to the in-memory layer keeps
# local dev and CI working without a Redis instance, same fallback
# pattern as DATABASE_URL -> sqlite above.
REDIS_URL = os.environ.get("REDIS_URL")
if REDIS_URL:
    CHANNEL_LAYERS = {
        "default": {
            "BACKEND": "channels_redis.core.RedisChannelLayer",
            "CONFIG": {"hosts": [REDIS_URL]},
        }
    }
    # Shared presence counters across Celery/API workers (lists.presence).
    CACHES = {
        "default": {
            "BACKEND": "django.core.cache.backends.redis.RedisCache",
            "LOCATION": REDIS_URL,
        }
    }
else:
    CHANNEL_LAYERS = {
        "default": {"BACKEND": "channels.layers.InMemoryChannelLayer"},
    }

DATABASES = {
    "default": dj_database_url.config(
        env="DATABASE_URL",
        default=f"sqlite:///{BASE_DIR / 'db.sqlite3'}",
    )
}

AUTH_USER_MODEL = "users.User"

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

REST_FRAMEWORK = {
    "DEFAULT_AUTHENTICATION_CLASSES": (
        "rest_framework_simplejwt.authentication.JWTAuthentication",
    ),
    "DEFAULT_PERMISSION_CLASSES": (
        "rest_framework.permissions.IsAuthenticated",
    ),
    "DEFAULT_PAGINATION_CLASS": "rest_framework.pagination.CursorPagination",
    "PAGE_SIZE": 20,
    "EXCEPTION_HANDLER": "shoppa_api.exceptions.shoppa_exception_handler",
    "DEFAULT_THROTTLE_CLASSES": (
        "shoppa_api.throttling.ReadRateThrottle",
    ),
    "DEFAULT_THROTTLE_RATES": {
        "auth": "10/minute",
        "reads": "120/minute",
    },
}

SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=15),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=14),
    "ROTATE_REFRESH_TOKENS": True,
}

CORS_ALLOWED_ORIGINS = [
    origin
    for origin in os.environ.get("CORS_ALLOWED_ORIGINS", "").split(",")
    if origin
]

# Shoppa is South-Africa-first; new users default to this region unless
# specified otherwise at registration (SRS FR-1.4, Architecture §5.1).
DEFAULT_REGION = "ZA"
DEFAULT_CURRENCY = "ZAR"

# Delivery platforms enabled per region (Architecture §7, FR-6.4).
DELIVERY_PLATFORMS_BY_REGION = {
    "ZA": [
        "checkers_6060",
        "pnp_asap",
        "spar_2u",
        "woolies_dash",
    ],
}

# Celery (Architecture §3): shares REDIS_URL with Channels. Without Redis,
# tasks execute eagerly so CI and sqlite-only dev never need a broker.
CELERY_BROKER_URL = os.environ.get("CELERY_BROKER_URL", REDIS_URL or "memory://")
CELERY_RESULT_BACKEND = os.environ.get(
    "CELERY_RESULT_BACKEND", REDIS_URL or "cache+memory://"
)
CELERY_ACCEPT_CONTENT = ["json"]
CELERY_TASK_SERIALIZER = "json"
CELERY_RESULT_SERIALIZER = "json"
CELERY_TIMEZONE = TIME_ZONE
if not REDIS_URL:
    CELERY_TASK_ALWAYS_EAGER = True
    CELERY_TASK_EAGER_PROPAGATES = True

# Periodic jobs (M8 scraper; used by celery beat when not using only DB schedules).
CELERY_BEAT_SCHEDULE = {
    "scrape-catalogue-prices-hourly": {
        "task": "price_intelligence.scrape_catalogue_prices",
        "schedule": 3600.0,
        "args": ("ZA",),
    },
}

# Stripe (Phase 5) — webhook signature secret; empty in dev.
STRIPE_WEBHOOK_SECRET = os.environ.get("STRIPE_WEBHOOK_SECRET", "")
STRIPE_SECRET_KEY = os.environ.get("STRIPE_SECRET_KEY", "")
STRIPE_CHECKOUT_SUCCESS_URL = os.environ.get(
    "STRIPE_CHECKOUT_SUCCESS_URL", "https://app.shoppa.app/subscription/success"
)
STRIPE_CHECKOUT_CANCEL_URL = os.environ.get(
    "STRIPE_CHECKOUT_CANCEL_URL", "https://app.shoppa.app/subscription/cancel"
)

# Firebase Cloud Messaging (Phase 2+ / M8) — server key for push dispatch.
FCM_SERVER_KEY = os.environ.get("FCM_SERVER_KEY", "")

# Typesense catalogue search (M8). Empty host = DB fallback only.
TYPESENSE_HOST = os.environ.get("TYPESENSE_HOST", "")
TYPESENSE_API_KEY = os.environ.get("TYPESENSE_API_KEY", "shoppa-dev-key")

# Scraper (M8): seed is default/CI; live requires SCRAPER_LIVE_ENABLED=true.
SCRAPER_MODE = os.environ.get("SCRAPER_MODE", "seed")
SCRAPER_LIVE_ENABLED = os.environ.get("SCRAPER_LIVE_ENABLED", "False") == "True"

# Product verify / Open Food Facts (barcode food verification).
# OFF_CLIENT_MODE: live | fixture (fixture for tests/CI without network).
OPEN_FOOD_FACTS_BASE_URL = os.environ.get(
    "OPEN_FOOD_FACTS_BASE_URL", "https://world.openfoodfacts.org"
)
OFF_USER_AGENT = os.environ.get(
    "OFF_USER_AGENT", "Shoppa/1.1 (product-verify; https://shoppa.app)"
)
OFF_HTTP_TIMEOUT_SECONDS = float(os.environ.get("OFF_HTTP_TIMEOUT_SECONDS", "1.5"))
OFF_CACHE_TTL_DAYS = int(os.environ.get("OFF_CACHE_TTL_DAYS", "7"))
OFF_NOT_FOUND_TTL_HOURS = int(os.environ.get("OFF_NOT_FOUND_TTL_HOURS", "24"))
OFF_CLIENT_MODE = os.environ.get("OFF_CLIENT_MODE", "live")

# Launch / ops (M7+)
SHOPPA_RELEASE_VERSION = os.environ.get("SHOPPA_RELEASE_VERSION", "1.1.0")

# Production hardening when DEBUG is off (staging/prod).
if not DEBUG:
    SECURE_BROWSER_XSS_FILTER = True
    SECURE_CONTENT_TYPE_NOSNIFF = True
    SESSION_COOKIE_SECURE = os.environ.get("SESSION_COOKIE_SECURE", "True") == "True"
    CSRF_COOKIE_SECURE = os.environ.get("CSRF_COOKIE_SECURE", "True") == "True"
    SECURE_SSL_REDIRECT = os.environ.get("SECURE_SSL_REDIRECT", "False") == "True"

# Pending list invites (and future password-reset mail). Console in dev;
# override EMAIL_BACKEND in production (e.g. SMTP or SES).
EMAIL_BACKEND = os.environ.get(
    "EMAIL_BACKEND", "django.core.mail.backends.console.EmailBackend"
)
DEFAULT_FROM_EMAIL = os.environ.get(
    "DEFAULT_FROM_EMAIL", "Shoppa <noreply@shoppa.app>"
)

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "verbose": {
            "format": "%(levelname)s %(name)s %(message)s",
        },
    },
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "formatter": "verbose",
        },
    },
    "root": {
        "handlers": ["console"],
        "level": os.environ.get("LOG_LEVEL", "INFO"),
    },
}

SENTRY_DSN = os.environ.get("SENTRY_DSN", "")
if SENTRY_DSN:
    try:
        import sentry_sdk
        from sentry_sdk.integrations.django import DjangoIntegration

        sentry_sdk.init(
            dsn=SENTRY_DSN,
            integrations=[DjangoIntegration()],
            traces_sample_rate=float(os.environ.get("SENTRY_TRACES_SAMPLE_RATE", "0.1")),
            send_default_pii=False,
            environment=os.environ.get("SENTRY_ENVIRONMENT", "production"),
            release=SHOPPA_RELEASE_VERSION,
        )
    except ImportError:
        pass

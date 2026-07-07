# Shoppa — Shopping Intelligence Platform

Monorepo for Shoppa: a mobile-first shopping intelligence platform (South Africa launch, multi-region architected). See `/docs` for the BRD, SRS, Solution Architecture, API Specification, Project Management Plan, QA Test Plan, and Implementation Plan.

## Structure

- `backend/` — Django REST Framework API (`shoppa_api`), organized into focused apps per the Solution Architecture.
- `app/` — Flutter application (`shoppa_app`) targeting iOS, Android, and Web.
- `docker-compose.yml` — containerized Postgres + Redis + API (Daphne) + Celery stack.

## Status (Milestone 6 — Ads & Monetization, July 2026)

**Released:** `v0.0.6-m6` on `main` (Milestone 6 complete)

**Active branch:** `milestone/m7-launch` (next)

| Area | M6 deliverables |
|------|-----------------|
| **House ads API** | `GET /v1/ads/placements`, `POST /v1/ads/impressions`, `POST /v1/ads/clicks` |
| **ads_free suppression** | Empty placements + no-op tracking for paid tiers (FR-10.4) |
| **Frequency capping** | Interstitial/rewarded capped per session (FR-10.5 / TC-10.5) |
| **Mobile ad slots** | Home + list banners, native in compare sheet, checkout interstitials |
| **Docker stack** | `docker compose up` runs migrate + seed + Daphne API + Celery |
| **Health probe** | `GET /v1/health/` for container orchestration |
| **M6 smoke** | `python scripts/m6_smoke.py` |

**Prior (M5 — `v0.0.5-m5`):** subscriptions, admin console, list export.

## Git branching

| Branch | Purpose |
|--------|---------|
| `main` | Phase-gate releases only |
| `milestone/m5-subscriptions` | Phase 5 subscriptions (`v0.0.5-m5`) |
| `milestone/m6-ads` | Phase 6 ads & Docker (`v0.0.6-m6`) |
| `milestone/m7-launch` | Phase 7 launch readiness (current) |
| `feat(scope): …` | Feature branches off the active milestone branch |

## Getting started

### Docker (recommended)

Runs the full backend in containers — Postgres, Redis, API, Celery worker + beat:

```bash
docker compose up -d --build
curl http://localhost:8000/v1/health/
```

The API entrypoint runs migrations and `seed_launch_data` on startup. Flutter against the emulator:

```bash
cd app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/v1
```

Stop and reset data:

```bash
docker compose down -v
```

### Backend (sqlite, no Redis)

```bash
cd backend
python -m venv .venv
# Windows: .venv\Scripts\activate
# macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
python manage.py migrate
python manage.py seed_launch_data
python manage.py runserver
```

### Backend (Docker infra only)

```bash
docker compose up -d postgres redis
cd backend
cp .env.example .env
# Set DATABASE_URL=postgres://shoppa:shoppa@localhost:5432/shoppa
# Set REDIS_URL=redis://localhost:6379/0
python manage.py migrate
python manage.py seed_launch_data
daphne -b 0.0.0.0 -p 8000 shoppa_api.asgi:application
# Separate terminals:
celery -A shoppa_api worker -l info
celery -A shoppa_api beat -l info
```

### App

```bash
cd app
flutter pub get
flutter run
# Optional API override:
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/v1
```

Requires Flutter **3.22+** / Dart **3.4+** (matches CI stable channel).

### Real-time (WebSockets)

List sync and chat require the ASGI server (not plain `runserver` WSGI):

```bash
cd backend
daphne -b 0.0.0.0 -p 8000 shoppa_api.asgi:application
```

### M6 demo flow

```bash
cd backend
python scripts/m6_smoke.py
# Or with Docker:
docker compose up -d --build
docker compose exec api python scripts/m6_smoke.py
# In the app (free tier): Mall banner, list banner, compare native ad, session interstitial
# Premium tier: no ads anywhere
```

### M5 demo flow

```bash
cd backend
python scripts/m5_smoke.py
# Profile → Plans & Billing; list → Export; admin users → Admin Console
```

## Conventions

- API: versioned at `/v1`, JSON, snake_case fields, UUID resource IDs, money as integer minor units + `currency_code`, cursor-based pagination.
- Commits: one feature per commit, `type(scope): summary` (e.g. `feat(backend): registration endpoint`).

## Open governance items (Implementation Plan §12)

Resolve before the phases they affect: POPIA review, scraping legal sign-off, localization scope for GA, launch concurrency targets for load tests, app-store submission buffer.
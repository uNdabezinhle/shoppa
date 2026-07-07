# Shoppa — Shopping Intelligence Platform

Monorepo for Shoppa: a mobile-first shopping intelligence platform (South Africa launch, multi-region architected). See `/docs` for the BRD, SRS, Solution Architecture, API Specification, Project Management Plan, QA Test Plan, and Implementation Plan.

## Structure

- `backend/` — Django REST Framework API (`shoppa_api`), organized into focused apps per the Solution Architecture.
- `app/` — Flutter application (`shoppa_app`) targeting iOS, Android, and Web.
- `docker-compose.yml` — local Postgres + Redis + API + Celery stack.

## Status (Sprint 0 — Platform, July 2026)

**Released:** `v0.0.1-m0` on `main` (Sprint 0 complete)

**Active branch:** `milestone/m1-foundation`

| Area | Done in Sprint 0 |
|------|------------------|
| **Git** | Milestone branching model; bootstrap tag `v0.0.0` |
| **Backend core** | Auth, lists, collaboration, price intelligence, promotions (pre-existing) |
| **Scaffolded apps** | `regions`, `delivery`, `chat`, `notifications`, `subscriptions`, `admin_tools`, `ads` |
| **Celery** | Worker + Beat config; eager mode without Redis |
| **Seed data** | `python manage.py seed_launch_data` (ZA region, 4 stores, 8 products) |
| **Stripe** | Webhook stub at `POST /v1/webhooks/stripe` |
| **Mobile** | Persistent auth (`flutter_secure_storage`), token refresh, `go_router` |
| **CI** | Backend + app workflows on `main` and `milestone/**`; staging deploy template |

**Next (M1):** tab shell, list CRUD UI, rate limits, expanded offline queue, profile screen.

## Git branching

| Branch | Purpose |
|--------|---------|
| `main` | Phase-gate releases only |
| `milestone/m1-foundation` | Phase 1 completion (current) |
| `feat(scope): …` | Feature branches off the active milestone branch |

## Getting started

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

### Backend (Docker Compose — Postgres + Redis + Celery)

```bash
docker compose up -d postgres redis
cd backend
cp .env.example .env
# Set DATABASE_URL=postgres://shoppa:shoppa@localhost:5432/shoppa
# Set REDIS_URL=redis://localhost:6379/0
python manage.py migrate
python manage.py seed_launch_data
python manage.py runserver
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

## Conventions

- API: versioned at `/v1`, JSON, snake_case fields, UUID resource IDs, money as integer minor units + `currency_code`, cursor-based pagination.
- Commits: one feature per commit, `type(scope): summary` (e.g. `feat(backend): registration endpoint`).

## Open governance items (Implementation Plan §12)

Resolve before the phases they affect: POPIA review, scraping legal sign-off, localization scope for GA, launch concurrency targets for load tests, app-store submission buffer.
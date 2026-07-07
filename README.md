# Shoppa — Shopping Intelligence Platform

Monorepo for Shoppa: a mobile-first shopping intelligence platform (South Africa launch, multi-region architected). See `/docs` for the BRD, SRS, Solution Architecture, API Specification, Project Management Plan, QA Test Plan, and Implementation Plan.

## Structure

- `backend/` — Django REST Framework API (`shoppa_api`), organized into focused apps per the Solution Architecture.
- `app/` — Flutter application (`shoppa_app`) targeting iOS, Android, and Web.
- `docker-compose.yml` — local Postgres + Redis + API + Celery stack.

## Status (Milestone 4 — Delivery, July 2026)

**Released:** `v0.0.4-m4` on `main` (Milestone 4 complete)

**Active branch:** `milestone/m5-subscriptions` (next)

| Area | Done in M4 |
|------|------------|
| **Adapter layer** | Common interface + four launch adapters (Checkers 60/60, PnP ASAP, SPAR 2U, Woolies Dash) |
| **Delivery quotes** | `GET /v1/lists/{id}/delivery-quotes` — ETA, fee, stock, affiliate URL |
| **Live delivery WS** | `ws/lists/{id}/delivery` — `quote.updated`, `availability.changed` |
| **Promotion badges** | `has_promotion` on list items with non-intrusive PROMO chip (FR-7.2) |
| **Delivery screen** | Compare tab CTA → `/delivery` with live quote refresh |
| **M4 smoke** | `python scripts/m4_smoke.py` validates quotes + affiliate tracking |

**Prior (M3 — `v0.0.3-m3`):** catalogue search, compare depth, promos, price-drop notifications.

## Git branching

| Branch | Purpose |
|--------|---------|
| `main` | Phase-gate releases only |
| `milestone/m3-intelligence` | Phase 3 price intelligence (`v0.0.3-m3`) |
| `milestone/m4-delivery` | Phase 4 delivery & fulfilment (`v0.0.4-m4`) |
| `milestone/m5-subscriptions` | Phase 5 subscriptions & professional tools (current) |
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

### Real-time (WebSockets)

List sync and chat require the ASGI server (not plain `runserver` WSGI):

```bash
cd backend
daphne -b 0.0.0.0 -p 8000 shoppa_api.asgi:application
```

### M3 demo flow

```bash
cd backend
python manage.py seed_launch_data
python scripts/m3_smoke.py
# In the app: add "Full Cream Milk 2L" from catalogue → Compare tab shows store savings
```

### M4 demo flow

```bash
cd backend
python manage.py seed_launch_data
python scripts/m4_smoke.py
# In the app: catalogue-linked list → Compare → "Compare delivery options"
```

## Conventions

- API: versioned at `/v1`, JSON, snake_case fields, UUID resource IDs, money as integer minor units + `currency_code`, cursor-based pagination.
- Commits: one feature per commit, `type(scope): summary` (e.g. `feat(backend): registration endpoint`).

## Open governance items (Implementation Plan §12)

Resolve before the phases they affect: POPIA review, scraping legal sign-off, localization scope for GA, launch concurrency targets for load tests, app-store submission buffer.
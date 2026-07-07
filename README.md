# Shoppa — Shopping Intelligence Platform

Monorepo for Shoppa: a mobile-first shopping intelligence platform (South Africa launch, multi-region architected). See `/docs` for the BRD, SRS, Solution Architecture, API Specification, Project Management Plan, QA Test Plan, and Implementation Plan.

## Structure

- `backend/` — Django REST Framework API (`shoppa_api`), organized into focused apps per the Solution Architecture.
- `app/` — Flutter application (`shoppa_app`) targeting iOS, Android, and Web.
- `docker-compose.yml` — local Postgres + Redis + API + Celery stack.

## Status (Milestone 3 — Intelligence, July 2026)

**Released:** `v0.0.2-m2` on `main` (Milestone 2 complete)

**Active branch:** `milestone/m3-intelligence` (in progress)

| Area | Done in M3 (so far) |
|------|---------------------|
| **Catalogue search** | `GET /v1/products?q=` — region-scoped product search |
| **Store price lookup** | `GET /v1/products/{id}/store-price?store_id=` for shop-mode prefill |
| **Catalogue-linked items** | Product picker on add-item; `product_id` sent to API |
| **Compare depth** | List selector, winner banner, savings vs worst store |
| **Session summary** | Spend + potential savings from comparison (FR-4.4 / FR-5.3) |
| **Promotions polish** | Seeded promos; Mall chip + Profile link to `/promotions` |
| **M3 smoke** | `python scripts/m3_smoke.py` validates savings + promos after seed |

**Prior (M2 — `v0.0.2-m2`):** presence, chat, collaborator avatars, WS reconnect.

**Remaining for M3 gate:** price-drop notification feed (TC-5.5), scraper task skeleton, tag `v0.0.3-m3`.

## Git branching

| Branch | Purpose |
|--------|---------|
| `main` | Phase-gate releases only |
| `milestone/m3-intelligence` | Phase 3 price intelligence (current) |
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

## Conventions

- API: versioned at `/v1`, JSON, snake_case fields, UUID resource IDs, money as integer minor units + `currency_code`, cursor-based pagination.
- Commits: one feature per commit, `type(scope): summary` (e.g. `feat(backend): registration endpoint`).

## Open governance items (Implementation Plan §12)

Resolve before the phases they affect: POPIA review, scraping legal sign-off, localization scope for GA, launch concurrency targets for load tests, app-store submission buffer.
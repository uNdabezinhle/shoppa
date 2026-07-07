# Shoppa — Shopping Intelligence Platform

Monorepo for Shoppa: a mobile-first shopping intelligence platform (South Africa launch, multi-region architected). See `/docs` for the BRD, SRS, Solution Architecture, API Specification, Project Management Plan, QA Test Plan, and Implementation Plan.

## Structure

- `backend/` — Django REST Framework API (`shoppa_api`), organized into focused apps per the Solution Architecture.
- `app/` — Flutter application (`shoppa_app`) targeting iOS, Android, and Web.
- `docker-compose.yml` — local Postgres + Redis + API + Celery stack.

## Status (Milestone 5 — Subscriptions & Professional, July 2026)

**Released:** `v0.0.5-m5` on `main` (Milestone 5 complete)

**Active branch:** `milestone/m6-ads` (next)

| Area | M5 deliverables |
|------|-----------------|
| **Subscription plans** | `GET /v1/subscriptions/plans`, `GET /v1/subscriptions/me` with feature flags |
| **Stripe checkout** | `POST /v1/subscriptions/checkout` (dev-mode fallback without Stripe keys) |
| **Webhook reconcile** | `checkout.session.completed`, `invoice.payment_failed`, `customer.subscription.deleted` |
| **Free-tier limits** | Max 3 owned lists enforced on `POST /lists` (FR-9.3) |
| **Professional mobile** | Scale-for-guests, publish toggle, discover/clone public lists |
| **List export** | `GET /v1/lists/{id}/export?type=csv|pdf` + mobile export menu (CSV clipboard, PDF snackbar) |
| **Admin console** | `GET /v1/admin/overview`, moderation queue, partner stores + mobile `/admin` |
| **M5 smoke** | `python scripts/m5_smoke.py` — plans, limits, checkout, downgrade, export, admin |

**Prior (M4 — `v0.0.4-m4`):** delivery adapters, live quote WS, promo badges.

## Git branching

| Branch | Purpose |
|--------|---------|
| `main` | Phase-gate releases only |
| `milestone/m3-intelligence` | Phase 3 price intelligence (`v0.0.3-m3`) |
| `milestone/m4-delivery` | Phase 4 delivery & fulfilment (`v0.0.4-m4`) |
| `milestone/m5-subscriptions` | Phase 5 subscriptions & professional tools (`v0.0.5-m5`) |
| `milestone/m6-ads` | Phase 6 ads & monetization (current) |
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

### M5 demo flow

```bash
cd backend
python manage.py migrate
python scripts/m5_smoke.py
# In the app: Profile → Plans & Billing; list → Export; admin users → Admin Console
```

## Conventions

- API: versioned at `/v1`, JSON, snake_case fields, UUID resource IDs, money as integer minor units + `currency_code`, cursor-based pagination.
- Commits: one feature per commit, `type(scope): summary` (e.g. `feat(backend): registration endpoint`).

## Open governance items (Implementation Plan §12)

Resolve before the phases they affect: POPIA review, scraping legal sign-off, localization scope for GA, launch concurrency targets for load tests, app-store submission buffer.
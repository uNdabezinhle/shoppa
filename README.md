# Shoppa — Shopping Intelligence Platform

Monorepo for Shoppa: a mobile-first shopping intelligence platform (South Africa launch, multi-region architected). See `/docs` for the BRD, SRS, Solution Architecture, API Specification, Project Management Plan, QA Test Plan, and Implementation Plan.

## Structure

- `backend/` — Django REST Framework API (`shoppa_api`), organized into focused apps per the Solution Architecture.
- `app/` — Flutter application (`shoppa_app`) targeting iOS, Android, and Web.
- `docker-compose.yml` — local Postgres + Redis + API + Celery stack.

## Status (Milestone 1 — Foundation, July 2026)

**Released:** `v0.0.1-m1` on `main` (Milestone 1 complete)

**Active branch:** `milestone/m2-collaboration`

| Area | Done in M1 |
|------|------------|
| **Backend auth** | `PATCH /users/me`, password-reset stub (`POST /auth/password-reset`), Personal→Professional upgrade (`POST /users/me/upgrade`) |
| **Rate limits** | Auth endpoints 10/min/IP; authenticated reads 120/min/user |
| **Mobile shell** | Bottom nav: Mall · Compare · Lists · Profile (`ShellRoute` + `go_router`) |
| **List CRUD UI** | Create/edit/delete lists; add/edit items (qty/unit/note); swipe-delete; drag-reorder |
| **Profile** | Account type, region, upgrade to Professional, logout |
| **Offline queue** | Expanded mutations: `update_item`, `delete_item`, `reorder_items` |
| **Mall tab** | Savings hero card driven by price comparison on latest list |

**Prior (Sprint 0 — `v0.0.1-m0`):** persistent auth, `go_router`, Celery scaffold, seed data, regions API, docker-compose, CI.

**Next (M2):** real-time collaboration polish, WebSocket UX, activity feed enhancements.

## Git branching

| Branch | Purpose |
|--------|---------|
| `main` | Phase-gate releases only |
| `milestone/m2-collaboration` | Phase 2 collaboration (current) |
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
# Shoppa — Shopping Intelligence Platform

Monorepo for Shoppa: a mobile-first shopping intelligence platform (South Africa launch, multi-region architected). See `/docs` for the BRD, SRS, Solution Architecture, API Specification, Project Management Plan, QA Test Plan, and Implementation Plan.

## Structure

- `backend/` — Django REST Framework API (`shoppa_api`), organized into focused apps per the Solution Architecture.
- `app/` — Flutter application (`shoppa_app`) targeting iOS, Android, and Web.
- `docker-compose.yml` — local Postgres + Redis + API + Celery stack.

## Status (Milestone 2 — Collaboration, July 2026)

**Released:** `v0.0.2-m2` on `main` (Milestone 2 complete)

**Active branch:** `milestone/m3-intelligence` (next)

| Area | Done in M2 |
|------|------------|
| **FR-3.1 Share** | View/edit permissions, collaborator sheet with live WS refresh |
| **FR-3.2 Real-time** | `ws/lists/{id}`, presence, reconnect/backoff, TC-3.2 propagation test |
| **FR-3.3 Activity** | Per-list feed with timestamps and pull-to-refresh |
| **FR-3.4 Chat** | `GET/POST /lists/{id}/messages`, `ws/lists/{id}/chat`, in-list chat sheet |
| **Mobile polish** | Presence banner, collaborator avatar stack, debounced refetch |
| **Load gate** | 32-subscriber fan-out test + `scripts/ws_loadtest.py` for staging |

**Prior (M1 — `v0.0.1-m1`):** tab shell, list CRUD UI, rate limits, profile, expanded offline queue.

**Next (M3):** price intelligence UX, promotions polish, comparison depth.

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

With Redis (`REDIS_URL` set), presence and broadcasts fan out across workers.

### Staging load probe (M2 gate)

```bash
cd backend
python scripts/ws_loadtest.py --list-id <uuid> --subscribers 50
```

## Conventions

- API: versioned at `/v1`, JSON, snake_case fields, UUID resource IDs, money as integer minor units + `currency_code`, cursor-based pagination.
- Commits: one feature per commit, `type(scope): summary` (e.g. `feat(backend): registration endpoint`).

## Open governance items (Implementation Plan §12)

Resolve before the phases they affect: POPIA review, scraping legal sign-off, localization scope for GA, launch concurrency targets for load tests, app-store submission buffer.
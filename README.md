# Shoppa — Shopping Intelligence Platform

Monorepo for Shoppa: a mobile-first shopping intelligence platform (South Africa launch, multi-region architected). See `/docs` for the BRD, SRS, Solution Architecture, API Specification, Project Management Plan, QA Test Plan, and Implementation Plan.

## Structure

- `backend/` — Django REST Framework API (`shoppa_api`), organized into focused apps per the Solution Architecture.
- `app/` — Flutter application (`shoppa_app`) targeting iOS, Android, and Web.
- `docker-compose.yml` — local Postgres + Redis + API (Daphne) + Celery stack.
- `docker-compose.prod.yml` — production-like stack with hardened defaults.

## Status (Milestone 7 — Launch Readiness, July 2026)

**Released:** `v1.0.0` on `main` (GA launch gate)

| Area | M7 deliverables |
|------|-----------------|
| **Launch meta** | `GET /v1/meta/launch` — version, milestones, feature manifest |
| **Health probes** | `GET /v1/health/` (liveness), `GET /v1/health/ready/` (DB readiness) |
| **Observability** | Correlation IDs (`X-Correlation-ID`), structured logging, optional Sentry |
| **POPIA** | `GET /v1/users/me/data-export`, `POST /v1/users/me/delete-account` + Profile UI |
| **Launch regression** | `python scripts/m7_smoke.py` runs m3–m6 smokes + platform checks |
| **CI launch gate** | `.github/workflows/launch-gate.yml` — full suite + Docker build |
| **Production Docker** | `docker-compose.prod.yml` + `backend/.env.production.example` |

**Prior (M6 — `v0.0.6-m6`):** house ads, Docker dev stack.

## Git branching

| Branch | Purpose |
|--------|---------|
| `main` | GA releases (`v1.0.0`) |
| `milestone/m6-ads` | Phase 6 ads & Docker (`v0.0.6-m6`) |
| `milestone/m7-launch` | Phase 7 launch readiness (`v1.0.0`) |
| `feat(scope): …` | Feature branches off the active milestone branch |

## Getting started

### Docker (recommended)

```bash
docker compose up -d --build
curl http://localhost:8000/v1/health/
curl http://localhost:8000/v1/health/ready/
curl http://localhost:8000/v1/meta/launch
```

Flutter against the emulator:

```bash
cd app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/v1
```

### Production-like Docker

```bash
cp backend/.env.production.example .env.production
# Edit SECRET_KEY and POSTGRES_PASSWORD
docker compose -f docker-compose.prod.yml --env-file .env.production up -d --build
```

### Backend (sqlite, no Redis)

```bash
cd backend
python -m venv .venv
# Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env
python manage.py migrate
python manage.py seed_launch_data
daphne -b 0.0.0.0 -p 8000 shoppa_api.asgi:application
```

### App

```bash
cd app
flutter pub get
flutter run
```

Requires Flutter **3.22+** / Dart **3.4+**.

### M7 launch gate

```bash
cd backend
python manage.py test
python scripts/m7_smoke.py
```

Profile → **Privacy & Data** for POPIA export and account deletion.

### Prior milestone smokes

```bash
python scripts/m3_smoke.py   # price comparison
python scripts/m4_smoke.py   # delivery quotes
python scripts/m5_smoke.py   # subscriptions
python scripts/m6_smoke.py   # house ads
```

## Conventions

- API: versioned at `/v1`, JSON, snake_case fields, UUID resource IDs, money as integer minor units + `currency_code`.
- Commits: `type(scope): summary` (e.g. `feat(platform): launch meta endpoint`).

## Open governance items (Implementation Plan §12)

Resolve before production cutover: POPIA legal review, scraping legal sign-off, localization scope, launch concurrency load-test targets, app-store submission buffer.
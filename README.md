# Shoppa — Shopping Intelligence Platform

Monorepo for Shoppa: a mobile-first shopping intelligence platform (South Africa launch, multi-region architected). See `/docs` in the project workspace for the BRD, SRS, Solution Architecture, API Specification, Project Management Plan, QA Test Plan, and Implementation Plan.

## Structure

- `backend/` — Django REST Framework API (`shoppa_api`), organized into focused apps per the Solution Architecture (users, lists, collaboration, price_intelligence, delivery, promotions, professional, chat, notifications, subscriptions, regions, admin_tools).
- `app/` — Flutter application (`shoppa_app`) targeting iOS, Android, and Web. The Web build serves the admin console; mobile serves personal/professional/store users.

## Status

Early Phase 1 (Foundation) work: accounts & authentication vertical slice (registration, JWT login, authenticated profile fetch) end-to-end across backend and mobile.

## Getting started

### Backend
```
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python manage.py migrate
python manage.py runserver
```

### App
```
cd app
flutter pub get
flutter run
```

## Conventions

- API: versioned at `/v1`, JSON, snake_case fields, UUID resource IDs, money as integer minor units + `currency_code`, cursor-based pagination. See the API Specification for the full contract.
- Commits: one feature per commit, `type(scope): summary` (e.g. `feat(backend): registration endpoint`).

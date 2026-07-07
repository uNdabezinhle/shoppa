#!/bin/sh
set -e

if [ -n "$DATABASE_URL" ]; then
  echo "Waiting for database..."
  python - <<'PY'
import os, sys, time
import dj_database_url
import psycopg2

url = os.environ.get("DATABASE_URL", "")
if not url.startswith("postgres"):
    sys.exit(0)

cfg = dj_database_url.parse(url)
for attempt in range(30):
    try:
        conn = psycopg2.connect(
            dbname=cfg["NAME"],
            user=cfg["USER"],
            password=cfg["PASSWORD"],
            host=cfg["HOST"],
            port=cfg.get("PORT") or 5432,
        )
        conn.close()
        break
    except psycopg2.OperationalError:
        time.sleep(1)
else:
    raise SystemExit("Database not ready")
PY
fi

python manage.py migrate --noinput

if [ "${SEED_LAUNCH_DATA:-true}" = "true" ]; then
  python manage.py seed_launch_data
fi

exec "$@"
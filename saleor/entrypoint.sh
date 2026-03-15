#!/bin/sh
set -e

# Default command is "api" — run migrations + collectstatic + uvicorn
# For worker/beat, docker-compose overrides CMD so this block is skipped

case "$1" in
  worker)
    echo "Starting Celery worker..."
    exec celery --app saleor.celeryconf:app worker -E --loglevel=info
    ;;
  beat)
    echo "Starting Celery beat scheduler..."
    exec celery --app saleor.celeryconf:app beat \
      --scheduler saleor.schedulers.schedulers.DatabaseScheduler \
      --loglevel=info
    ;;
  *)
    echo "Running database migrations..."
    python manage.py migrate --noinput

    echo "Collecting static files..."
    python manage.py collectstatic --noinput

    echo "Starting Saleor API server..."
    exec uvicorn saleor.asgi:application \
      --host 0.0.0.0 \
      --port 8000 \
      --workers "${UVICORN_WORKERS:-2}"
    ;;
esac

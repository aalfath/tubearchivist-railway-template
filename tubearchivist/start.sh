#!/bin/bash
# Start script for Tube Archivist on Railway (replaces upstream's docker_assets/run.sh).
set -e
cd /app

log() { echo "railway-template: $*"; }

# All state lives on the one Railway volume at /data:
#   /data/cache   SQLite (users, schedules), thumbnails, backups, download cache
#   /data/youtube downloaded media
DATA_DIR="${RAILWAY_VOLUME_MOUNT_PATH:-/data}"
export TA_CACHE_DIR="${TA_CACHE_DIR:-$DATA_DIR/cache}"
export TA_MEDIA_DIR="${TA_MEDIA_DIR:-$DATA_DIR/youtube}"
rm -rf "$DATA_DIR/lost+found" 2>/dev/null || true
mkdir -p "$TA_CACHE_DIR" "$TA_MEDIA_DIR"

export TA_PORT="${PORT:-${TA_PORT:-8000}}"
# Railway's health check sends Host: healthcheck.railway.app; Django only accepts
# the hosts listed in TA_HOST.
case " $TA_HOST " in *healthcheck.railway.app*) ;; *) export TA_HOST="${TA_HOST:-localhost} healthcheck.railway.app" ;; esac

# Each web or Celery worker is a ~100 MB Python process. Defaults fit a 0.5 GB
# service; raise TA_WEB_WORKERS / TA_CELERY_CONCURRENCY on bigger plans.
WEB_WORKERS="${TA_WEB_WORKERS:-1}"
CELERY_CONCURRENCY="${TA_CELERY_CONCURRENCY:-1}"
if [[ -n "$DJANGO_DEBUG" ]]; then LOGLEVEL=DEBUG; UVLOG=info; else LOGLEVEL=INFO; UVLOG=warning; fi

for v in TA_PASSWORD ELASTIC_PASSWORD ES_URL REDIS_CON; do
  if [[ -z "${!v}" ]]; then log "$v is empty; refusing to start" >&2; exit 1; fi
done

# Wait for Elasticsearch and Redis (they start at the same time on a first deploy).
log "waiting for Elasticsearch at $ES_URL"
for i in $(seq 1 120); do
  if curl -fsS -o /dev/null -m 5 -u "${ELASTIC_USER:-elastic}:$ELASTIC_PASSWORD" "$ES_URL/_cluster/health?wait_for_status=yellow&timeout=4s"; then
    log "Elasticsearch is up"; break
  fi
  if [[ $i -eq 120 ]]; then log "Elasticsearch did not answer in 10 minutes" >&2; exit 1; fi
  sleep 5
done
log "waiting for Redis"
python - <<'PY'
import os, sys, time, redis
c = redis.from_url(os.environ["REDIS_CON"])
for i in range(120):
    try:
        c.ping(); print("railway-template: Redis is up"); sys.exit(0)
    except Exception as e:
        err = e; time.sleep(5)
print(f"railway-template: Redis did not answer in 10 minutes: {err}", file=sys.stderr); sys.exit(1)
PY

# Optional: refresh yt-dlp on start (TA_AUTO_UPDATE_YTDLP=release|nightly).
YTDLP_UPDATE_DIR=/tmp/ta-yt-dlp
if [[ "${TA_AUTO_UPDATE_YTDLP,,}" =~ ^(release|nightly)$ ]]; then
  log "updating yt-dlp (${TA_AUTO_UPDATE_YTDLP,,})"
  preflag=""; [[ "${TA_AUTO_UPDATE_YTDLP,,}" == "nightly" ]] && preflag="--pre"
  if python -m pip install --no-cache-dir --disable-pip-version-check -q --target="$YTDLP_UPDATE_DIR" --upgrade $preflag "yt-dlp[default]"; then
    export PYTHONPATH="$YTDLP_UPDATE_DIR${PYTHONPATH:+:$PYTHONPATH}"
  else
    log "yt-dlp update failed, using the bundled version"
  fi
fi

# Upstream setup steps (same order as run.sh). Any failure exits non-zero.
python manage.py ta_stop_on_error
python manage.py migrate --noinput
python manage.py ta_envcheck
python manage.py ta_connection
python manage.py ta_startup

PIDS=()
stop_all() { for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null || true; done; }
trap 'log "stopping"; stop_all; wait; exit 0' TERM INT

celery -A task.celery worker --loglevel=$LOGLEVEL --concurrency "$CELERY_CONCURRENCY" \
  --max-tasks-per-child 5 --max-memory-per-child 150000 &
PIDS+=($!)
./beat_auto_spawn.sh &
PIDS+=($!)
log "starting web server on port $TA_PORT ($WEB_WORKERS workers, $CELERY_CONCURRENCY Celery workers)"
uvicorn config.asgi:application --host 0.0.0.0 --port "$TA_PORT" --workers "$WEB_WORKERS" --log-level "$UVLOG" &
PIDS+=($!)

# If any process exits, stop the rest and exit non-zero so Railway restarts us.
set +e
wait -n "${PIDS[@]}"
rc=$?
log "a process exited (code $rc); stopping the container" >&2
stop_all
sleep 2
exit 1

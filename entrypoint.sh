#!/usr/bin/env bash
set -e

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}
#---------------------------------------------------
BALANCER_SRC="${BALANCER_SRC:-/bin/balancer}"
BALANCER_DIR="${BALANCER_DIR:-/balancer}"
BALANCER_BIN="${BALANCER_DIR}/balancer"
BALANCER_PID=""

start_balancer() {
  mkdir -p "$BALANCER_DIR"

  if [ ! -x "$BALANCER_SRC" ]; then
    log "[ERR] balancer binary not found at $BALANCER_SRC"
    return 1
  fi

  # отдельный супервизорный цикл в фоне
  (
    while true; do
      # копируем свежий бинарь перед каждым запуском (на случай обновлений)
      cp -f "$BALANCER_SRC" "$BALANCER_BIN"
      chmod +x "$BALANCER_BIN"

      log "Starting balancer from $BALANCER_BIN ..."
      "$BALANCER_BIN" &
      BALANCER_PID=$!
      log "balancer PID = $BALANCER_PID"

      # ждём завершения процесса
      wait "$BALANCER_PID"
      exit_code=$?
      log "balancer exited with code $exit_code"

      # если вышел нормально (0) — выходим из цикла, не перезапускаем
      if [ "$exit_code" -eq 0 ]; then
        log "balancer exited normally, supervisor will stop"
        break
      fi

      # если упал — ждём и перезапускаем
      log "balancer crashed, restarting in 5s..."
      sleep 5
    done
  ) &
}

restart_balancer() {
  if [ -n "$BALANCER_PID" ] && kill -0 "$BALANCER_PID" 2>/dev/null; then
    log "Stopping balancer (PID=$BALANCER_PID)..."
    kill "$BALANCER_PID" || true
    # не вызываем start_balancer здесь — супервизор сам его перезапустит
  else
    log "No running balancer to stop (supervisor will start it if needed)"
  fi
}
#---------------------------------------------------


# ---------- 1) Генерация domain.txt ----------
log "Running generate_domain.py..."
python3 /scripts/generate_domain.py

DOMAIN_TXT_PATH="${DOMAIN_DIR:-/server_data}/domain.txt"
log "Domain file expected at: ${DOMAIN_TXT_PATH}"



# ---------- 3) Старт balancer ----------
log "Starting balancer service..."
start_balancer

# ---------- 4) Вотчер на изменения сертификатов ----------
(
  log "Starting SSL watcher for balancer..."
  LAST_HASH=""

  while true; do
    # считаем хэш всего содержимого в /opt/ssl
    CURRENT_HASH="$(find /opt/ssl -maxdepth 1 -type f -print0 2>/dev/null | sort -z | xargs -0 sha256sum 2>/dev/null || echo 'no_files')"

    if [ -n "$LAST_HASH" ] && [ "$CURRENT_HASH" != "$LAST_HASH" ]; then
      log "SSL files changed, restarting balancer..."
      restart_balancer
    fi

    LAST_HASH="$CURRENT_HASH"
    sleep 10
  done
) &




# ---------- 4) Старт Redis (главный процесс) ----------
log "Starting Redis..."
exec /Redis/redis-server /Redis/redis.conf

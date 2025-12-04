#!/usr/bin/env bash
set -e

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# ---------- 1) Генерация domain.txt ----------
log "Running generate_domain.py..."
python3 /scripts/generate_domain.py

DOMAIN_TXT_PATH="${DOMAIN_DIR:-/server_data}/domain.txt"
log "Domain file expected at: ${DOMAIN_TXT_PATH}"

# ---------- 2) TLS stage (deSEC + lego) ----------
log "TLS stage (deSEC) after setconfiguration..."

: "${EMAIL:?EMAIL env is required for ACME}"
: "${DESEC_TOKEN:?DESEC_TOKEN env is required for deSEC}"

LEGO_PATH="${LEGO_PATH:-/data/lego}"
OUT_DIR="/opt/ssl"
mkdir -p "$LEGO_PATH" "$OUT_DIR"

LOCK_FILE="$LEGO_PATH/.acme.lock"
mkdir -p "$(dirname "$LOCK_FILE")"
exec 9>"$LOCK_FILE"
flock -x 9 || true
log "acquired global ACME lock: $LOCK_FILE"

# --- Домены ---
DOMAINS_FROM_ENV="${DOMAINS:-}"
DOMAINS_FROM_FILE=""

if [ -f "$DOMAIN_TXT_PATH" ]; then
  DOMAINS_FROM_FILE="$(tr -d ' \n\r' <"$DOMAIN_TXT_PATH")"
fi

DOMAINS_FINAL="$DOMAINS_FROM_ENV"
if [ -z "$DOMAINS_FINAL" ]; then
  DOMAINS_FINAL="$DOMAINS_FROM_FILE"
fi

if [ -z "$DOMAINS_FINAL" ]; then
  echo "[ERR] no domains found. Set DOMAINS env or ensure $DOMAIN_TXT_PATH exists" >&2
  exit 1
fi

log "domains for cert: $DOMAINS_FINAL"

# "a,b,c" -> "--domains a --domains b --domains c"
domain_args=""
OLD_IFS="$IFS"; IFS=","
for d in $DOMAINS_FINAL; do
  d="$(echo "$d" | tr -d ' \n\r')"
  [ -n "$d" ] && domain_args="$domain_args --domains $d"
done
IFS="$OLD_IFS"

# Берём первый домен как основной CN
first_domain="$(echo "$DOMAINS_FINAL" | cut -d',' -f1 | tr -d ' \n\r')"

issue_cert() {
  log "issuing cert via lego (desec)"
  /usr/local/bin/lego \
    --accept-tos \
    --email="$EMAIL" \
    --dns="desec" \
    $domain_args \
    --path="$LEGO_PATH" \
    run
}

renew_cert() {
  log "renewing cert if needed..."
  /usr/local/bin/lego \
    --email="$EMAIL" \
    --dns="desec" \
    $domain_args \
    --path="$LEGO_PATH" \
    renew \
    --days "${RENEW_BEFORE_DAYS:-30}"
}

copy_from_lego() {
  local dom="$1"
  local crt="$LEGO_PATH/certificates/${dom}.crt"
  local key="$LEGO_PATH/certificates/${dom}.key"

  if [ ! -f "$crt" ] || [ ! -f "$key" ]; then
    log "[WARN] copy_from_lego: no cert/key for $dom"
    return 1
  fi

  cp -f "$crt" "$OUT_DIR/sert.crt"
  cp -f "$key" "$OUT_DIR/sert.key"
  cat "$OUT_DIR/sert.crt" "$OUT_DIR/sert.key" > "$OUT_DIR/sert.crt.key"
  chmod 600 "$OUT_DIR/sert.key" "$OUT_DIR/sert.crt.key"

  log "wrote LE cert to:"
  log "  $OUT_DIR/sert.crt"
  log "  $OUT_DIR/sert.key"
  log "  $OUT_DIR/sert.crt.key"
}

try_issue() {
  local max_tries="${ISSUE_MAX_TRIES:-5}"
  local i=1
  while [ "$i" -le "$max_tries" ]; do
    if issue_cert; then
      return 0
    fi
    log "[WARN] issue failed, retry $i/$max_tries after 60s..."
    sleep 60
    i=$((i+1))
  done
  return 1
}

# 2.1) Первичный сертификат
if [ ! -d "$LEGO_PATH/certificates" ] || [ -z "$(ls -A "$LEGO_PATH/certificates" 2>/dev/null)" ]; then
  log "no existing certificates in $LEGO_PATH, trying to issue..."
  if ! try_issue; then
    echo "[ERR] initial LE issue failed after multiple attempts" >&2
    exit 1
  fi
else
  log "certificates already exist in $LEGO_PATH, skipping initial issue"
fi

# 2.2) Копируем сертификат в /opt/ssl
if ! copy_from_lego "$first_domain"; then
  echo "[ERR] lego did not produce cert/key for $first_domain" >&2
  exit 1
fi

# 2.3) Background auto-renew (без haproxy-части)
(
  RENEW_INTERVAL="${RENEW_INTERVAL:-21600}"   # 6 часов
  while true; do
    sleep "$RENEW_INTERVAL"

    log "auto-renew: running lego renew..."
    if renew_cert; then
      if copy_from_lego "$first_domain"; then
        log "auto-renew: cert renewed and files updated"
      else
        log "[WARN] auto-renew: LE cert files missing after renew"
      fi
    else
      log "[WARN] auto-renew: lego renew failed, will retry next interval"
    fi
  done
) &


# ---------- 4) Старт Redis (главный процесс) ----------
log "Starting Redis..."
exec /Redis/redis-server /Redis/redis.conf

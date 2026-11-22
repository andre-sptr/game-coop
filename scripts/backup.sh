#!/usr/bin/env bash
set -euo pipefail
umask 077
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

APP_DIR="/opt/apps/game-coop"
ENV_FILE="$APP_DIR/.env"
BACKUP_DIR="$APP_DIR/backups"
PG_CONTAINER="1Panel-postgresql-3oWY"
RETENTION_DAYS=14
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

read_env_var() {
  local target_key="$1"
  local line="" val="" found_val=""
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "Error: Missing $ENV_FILE" >&2
    return 1
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    if [[ "$line" == "${target_key}="* ]]; then
      val="${line#*=}"
      if [[ ${#val} -ge 2 ]]; then
        if [[ "${val:0:1}" == '"' && "${val: -1}" == '"' ]]; then
          val="${val:1:${#val}-2}"
        elif [[ "${val:0:1}" == "'" && "${val: -1}" == "'" ]]; then
          val="${val:1:${#val}-2}"
        fi
      fi
      found_val="$val"
    fi
  done < "$ENV_FILE"
  printf '%s' "$found_val"
}

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

ROMM_DB_DRIVER="$(read_env_var ROMM_DB_DRIVER)"
ROMM_DB_DRIVER="${ROMM_DB_DRIVER:-postgresql}"
DB_NAME="$(read_env_var DB_NAME)"
DB_USER="$(read_env_var DB_USER)"
DB_PASSWD="$(read_env_var DB_PASSWD)"

for var_name in DB_NAME DB_USER DB_PASSWD; do
  var_val="${!var_name}"
  if [[ -z "$var_val" || "$var_val" == CHANGE_ME_* ]]; then
    echo "Error: $var_name is unset or still a placeholder in .env" >&2
    exit 1
  fi
done

DB_TMP="$(mktemp "$BACKUP_DIR/.tmp-romm-db.XXXXXX.sql.gz")"
ARC_TMP=""
trap 'unset PGPASSWORD MYSQL_PWD || true; rm -f "${DB_TMP:-}" "${ARC_TMP:-}"' EXIT

case "$ROMM_DB_DRIVER" in
  postgresql)
    export PGPASSWORD="$DB_PASSWD"
    docker exec -i -e PGPASSWORD "$PG_CONTAINER" \
      pg_dump -U "$DB_USER" -d "$DB_NAME" --clean --if-exists | gzip -9 > "$DB_TMP"
    unset PGPASSWORD
    ;;
  mariadb|mysql)
    export MYSQL_PWD="$DB_PASSWD"
    docker exec -i -e MYSQL_PWD romm-db \
      mariadb-dump -u "$DB_USER" --single-transaction "$DB_NAME" | gzip -9 > "$DB_TMP"
    unset MYSQL_PWD
    ;;
  *)
    echo "Error: Unsupported ROMM_DB_DRIVER '$ROMM_DB_DRIVER'" >&2
    exit 1
    ;;
esac

if [[ ! -s "$DB_TMP" ]] || ! gzip -t "$DB_TMP"; then
  echo "Error: Database dump is empty or corrupt" >&2
  exit 1
fi

chmod 600 "$DB_TMP"
DB_DEST="$BACKUP_DIR/romm-db-${TIMESTAMP}.sql.gz"
mv -f "$DB_TMP" "$DB_DEST"
DB_SIZE="$(du -h "$DB_DEST" | awk '{print $1}')"

TARGETS=()
[[ -d "$APP_DIR/data/assets" ]] && TARGETS+=("data/assets")
[[ -f "$APP_DIR/config/config.yml" ]] && TARGETS+=("config/config.yml")

ARC_INFO="skipped (no assets/config yet)"
if [[ ${#TARGETS[@]} -gt 0 ]]; then
  ARC_TMP="$(mktemp "$BACKUP_DIR/.tmp-saves-config.XXXXXX.tar.gz")"
  tar -C "$APP_DIR" -czf "$ARC_TMP" "${TARGETS[@]}"
  if [[ ! -s "$ARC_TMP" ]] || ! gzip -t "$ARC_TMP"; then
    echo "Error: Saves/config archive is empty or corrupt" >&2
    exit 1
  fi
  chmod 600 "$ARC_TMP"
  ARC_DEST="$BACKUP_DIR/romm-saves-config-${TIMESTAMP}.tar.gz"
  mv -f "$ARC_TMP" "$ARC_DEST"
  ARC_SIZE="$(du -h "$ARC_DEST" | awk '{print $1}')"
  ARC_INFO="$(basename "$ARC_DEST") (${ARC_SIZE})"
fi

find "$BACKUP_DIR" -maxdepth 1 -type f \
  \( -name 'romm-db-*.sql.gz' -o -name 'romm-saves-config-*.tar.gz' \) \
  -mtime +"$RETENTION_DAYS" -delete

printf '[%s] Backup complete: db=%s (%s), archive=%s\n' \
  "$(date -Iseconds)" "$(basename "$DB_DEST")" "$DB_SIZE" "$ARC_INFO"

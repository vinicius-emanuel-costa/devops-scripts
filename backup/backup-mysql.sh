#!/bin/bash
# ============================================================
# MySQL/MariaDB Backup Script with Rotation
# Creates compressed backups and removes old ones
# Usage: bash backup-mysql.sh [--config /path/to/backup.conf]
#
# Recommended cron (daily at 2am):
#   0 2 * * * /path/to/backup-mysql.sh >> /var/log/mysql-backup.log 2>&1
# ============================================================

set -euo pipefail

# --- Default Configuration ---
DB_HOST="localhost"
DB_PORT="3306"
DB_USER="backup_user"
DB_PASS=""                         # Set via config file or environment
DATABASES="all"                    # "all" or space-separated: "db1 db2 db3"
BACKUP_DIR="/backup/mysql"
RETENTION_DAYS=30
COMPRESS="gzip"                    # gzip or zstd
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${GREEN}[OK]${NC} $1"; }
warn() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${RED}[ERROR]${NC} $1"; exit 1; }

# --- Parse arguments ---
CONFIG_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG_FILE="$2"; shift 2 ;;
    --dir)    BACKUP_DIR="$2"; shift 2 ;;
    --days)   RETENTION_DAYS="$2"; shift 2 ;;
    --help)
      echo "Usage: $0 [options]"
      echo "  --config   Path to config file"
      echo "  --dir      Backup directory (default: /backup/mysql)"
      echo "  --days     Retention days (default: 30)"
      exit 0
      ;;
    *) err "Unknown option: $1" ;;
  esac
done

# --- Load config file if provided ---
if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
  log "Loaded config: $CONFIG_FILE"
fi

# --- Use environment variable fallback for password ---
DB_PASS="${DB_PASS:-$MYSQL_PWD}"

if [ -z "$DB_PASS" ]; then
  err "Database password not set. Use config file or MYSQL_PWD env var."
fi

# --- Validate tools ---
for cmd in mysqldump mysql; do
  if ! command -v "$cmd" &>/dev/null; then
    err "$cmd not found. Install mysql-client."
  fi
done

# --- Create backup directory ---
mkdir -p "$BACKUP_DIR"

# --- Get database list ---
get_databases() {
  if [ "$DATABASES" = "all" ]; then
    mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASS" \
      -e "SHOW DATABASES;" -s --skip-column-names 2>/dev/null | \
      grep -Ev '^(information_schema|performance_schema|sys|mysql)$'
  else
    echo "$DATABASES" | tr ' ' '\n'
  fi
}

# --- Compression command ---
compress_cmd() {
  case "$COMPRESS" in
    zstd)  echo "zstd -T0 -q" ;;
    gzip)  echo "gzip" ;;
    *)     echo "gzip" ;;
  esac
}

compress_ext() {
  case "$COMPRESS" in
    zstd) echo ".zst" ;;
    *)    echo ".gz" ;;
  esac
}

# --- Backup ---
TOTAL=0
FAILED=0
BACKUP_SIZE=0

log "Starting MySQL backup..."
log "Host: ${DB_HOST}:${DB_PORT} | User: ${DB_USER}"
log "Backup dir: ${BACKUP_DIR}"

while IFS= read -r DB; do
  [ -z "$DB" ] && continue
  TOTAL=$((TOTAL + 1))

  OUTFILE="${BACKUP_DIR}/${DB}_${TIMESTAMP}.sql$(compress_ext)"
  log "Backing up: ${DB}..."

  if mysqldump \
    -h "$DB_HOST" \
    -P "$DB_PORT" \
    -u "$DB_USER" \
    -p"$DB_PASS" \
    --single-transaction \
    --routines \
    --triggers \
    --events \
    --quick \
    --lock-tables=false \
    "$DB" 2>/dev/null | $(compress_cmd) > "$OUTFILE"; then

    SIZE=$(du -h "$OUTFILE" | cut -f1)
    log "  Done: ${OUTFILE} (${SIZE})"
    BACKUP_SIZE=$((BACKUP_SIZE + $(stat -c%s "$OUTFILE")))
  else
    FAILED=$((FAILED + 1))
    warn "  FAILED: ${DB}"
    rm -f "$OUTFILE"
  fi
done < <(get_databases)

# --- Rotation: remove old backups ---
log "Removing backups older than ${RETENTION_DAYS} days..."
REMOVED=$(find "$BACKUP_DIR" -name "*.sql.gz" -o -name "*.sql.zst" -mtime +"$RETENTION_DAYS" -delete -print | wc -l)
log "Removed ${REMOVED} old backup(s)"

# --- Summary ---
TOTAL_SIZE=$(echo "scale=2; $BACKUP_SIZE / 1048576" | bc 2>/dev/null || echo "N/A")

echo ""
echo "========================================"
echo " MySQL Backup Summary"
echo "========================================"
echo " Date:       $(date '+%Y-%m-%d %H:%M:%S')"
echo " Databases:  ${TOTAL} total, $((TOTAL - FAILED)) success, ${FAILED} failed"
echo " Total Size: ${TOTAL_SIZE} MB"
echo " Retention:  ${RETENTION_DAYS} days"
echo " Removed:    ${REMOVED} old backup(s)"
echo "========================================"

if [ "$FAILED" -gt 0 ]; then
  warn "Some backups failed! Check logs above."
  exit 1
fi

log "All backups completed successfully."

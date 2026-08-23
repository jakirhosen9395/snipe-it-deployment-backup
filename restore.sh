#!/bin/bash
# restore.sh
# Restores Snipe-IT database + storage/.env from an encrypted backup,
# regardless of which source it came from (local / remote / s3) — you just
# point it at the two .gpg files already sitting on THIS machine.
#
# For remote/S3 sources: first copy the .sql.gpg and .tar.gz.gpg files onto
# the restore target server (via scp or aws s3 cp), THEN run this script.
#
# Usage:
#   sudo ./restore.sh /path/to/snipeit_db_TIMESTAMP.sql.gpg \
#                      /path/to/snipeit_storage_TIMESTAMP.tar.gz.gpg
#
# This script does NOT install Snipe-IT itself — run the normal install
# steps first (PHP, MariaDB, nginx, Composer, git clone, database creation)
# up through Step 4 (database creation) of the install guide, then use this
# script to restore data into that fresh install.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DB_ENC_FILE="${1:-}"
STORAGE_ENC_FILE="${2:-}"

if [ -z "${DB_ENC_FILE}" ] || [ -z "${STORAGE_ENC_FILE}" ]; then
  echo "Usage: sudo ./restore.sh <db_backup.sql.gpg> <storage_backup.tar.gz.gpg>"
  exit 1
fi

if [ ! -f "${DB_ENC_FILE}" ]; then
  echo "FATAL: ${DB_ENC_FILE} not found."
  exit 1
fi
if [ ! -f "${STORAGE_ENC_FILE}" ]; then
  echo "FATAL: ${STORAGE_ENC_FILE} not found."
  exit 1
fi

# ---- Configuration (edit these or export as environment variables before running) ----
DB_NAME="${DB_NAME:-snipeit_db}"
DB_USER="${DB_USER:-root}"
SNIPEIT_DIR="${SNIPEIT_DIR:-/var/www/html/snipe-it}"
PASSPHRASE_FILE="${PASSPHRASE_FILE:-/root/.secrets/backup_passphrase.txt}"
WEB_USER="${WEB_USER:-www-data}"
TMP_DIR="${TMP_DIR:-/tmp/snipeit_restore_$(date +%s)}"

if [ ! -f "${PASSPHRASE_FILE}" ]; then
  echo "FATAL: passphrase file not found at ${PASSPHRASE_FILE}."
  echo "You must have the original backup passphrase available to decrypt these files."
  exit 1
fi

mkdir -p "${TMP_DIR}"
echo "[$(date '+%F %T')] Using temp directory: ${TMP_DIR}"

DB_SQL="${TMP_DIR}/db_restore.sql"
STORAGE_TAR="${TMP_DIR}/storage_restore.tar.gz"

echo "[$(date '+%F %T')] Decrypting database backup..."
gpg --batch --yes --passphrase-file "${PASSPHRASE_FILE}" \
  --decrypt -o "${DB_SQL}" "${DB_ENC_FILE}"

echo "[$(date '+%F %T')] Decrypting storage backup..."
gpg --batch --yes --passphrase-file "${PASSPHRASE_FILE}" \
  --decrypt -o "${STORAGE_TAR}" "${STORAGE_ENC_FILE}"

echo "[$(date '+%F %T')] Verifying decrypted SQL looks valid..."
if ! head -5 "${DB_SQL}" | grep -qi "MariaDB dump\|MySQL dump\|CREATE"; then
  echo "WARNING: decrypted file does not look like a valid SQL dump. Aborting before touching the database."
  echo "First 5 lines were:"
  head -5 "${DB_SQL}"
  exit 1
fi

read -r -p "About to restore into database '${DB_NAME}'. This will overwrite existing data. Continue? [y/N] " confirm
if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
  echo "Aborted by user."
  rm -rf "${TMP_DIR}"
  exit 0
fi

echo "[$(date '+%F %T')] Restoring database..."
mysql -u "${DB_USER}" -p "${DB_NAME}" < "${DB_SQL}"
echo "[$(date '+%F %T')] Database restored."

echo "[$(date '+%F %T')] Restoring storage/ and .env into ${SNIPEIT_DIR}..."
tar -xzf "${STORAGE_TAR}" -C "${SNIPEIT_DIR}"
chown -R "${WEB_USER}:${WEB_USER}" "${SNIPEIT_DIR}/storage" "${SNIPEIT_DIR}/.env"
chmod -R 775 "${SNIPEIT_DIR}/storage" "${SNIPEIT_DIR}/public/uploads" 2>/dev/null || true
echo "[$(date '+%F %T')] Storage restored."

echo "[$(date '+%F %T')] Clearing Laravel config/cache..."
sudo -u "${WEB_USER}" php "${SNIPEIT_DIR}/artisan" config:clear
sudo -u "${WEB_USER}" php "${SNIPEIT_DIR}/artisan" cache:clear

echo "[$(date '+%F %T')] Cleaning up temporary decrypted files..."
rm -rf "${TMP_DIR}"

echo "[$(date '+%F %T')] Restore complete. Load the site in a browser to verify."

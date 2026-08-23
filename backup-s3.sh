#!/bin/bash
# backup-s3.sh
# Continuously backs up Snipe-IT (DB + storage/.env) to an S3 bucket,
# encrypted with GPG before it ever leaves this machine.
# Interval and all paths are controlled via s3.env.
#
# Run manually once to test:   sudo ./backup-s3.sh --once
# Run continuously (normally done via systemd, see README Part 5):
#                               sudo ./backup-s3.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/s3.env"

if [ ! -f "${ENV_FILE}" ]; then
  echo "FATAL: ${ENV_FILE} not found." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "${ENV_FILE}"
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/common.sh"

require_vars DB_NAME STORAGE_DIR LOCAL_STAGING_DIR PASSPHRASE_FILE \
  S3_BUCKET S3_PREFIX AWS_REGION RETENTION_DAYS BACKUP_INTERVAL_SECONDS LOG_FILE

export AWS_DEFAULT_REGION="${AWS_REGION}"

mkdir -p "${LOCAL_STAGING_DIR}"
touch "${LOG_FILE}"

run_backup_cycle() {
  local ts
  ts=$(date +%F_%H-%M-%S)

  local db_dump="${LOCAL_STAGING_DIR}/snipeit_db_${ts}.sql"
  local storage_tar="${LOCAL_STAGING_DIR}/snipeit_storage_${ts}.tar.gz"
  local db_enc="${db_dump}.gpg"
  local storage_enc="${storage_tar}.gpg"

  log "---- Starting S3 backup cycle (${ts}) ----"

  if ! dump_database "${db_dump}"; then
    log_error "Backup cycle aborted: database dump failed."
    return 1
  fi

  if ! archive_storage "${storage_tar}"; then
    log_error "Backup cycle aborted: storage archive failed."
    shred_plaintext "${db_dump}"
    return 1
  fi

  encrypt_file "${db_dump}" "${db_enc}" || { shred_plaintext "${db_dump}" "${storage_tar}"; return 1; }
  encrypt_file "${storage_tar}" "${storage_enc}" || { shred_plaintext "${db_dump}" "${storage_tar}"; return 1; }

  shred_plaintext "${db_dump}" "${storage_tar}"

  if ! aws s3 cp "${db_enc}" "s3://${S3_BUCKET}/${S3_PREFIX}/$(basename "${db_enc}")" >>"${LOG_FILE}" 2>&1; then
    log_error "S3 upload failed for ${db_enc}. Keeping local copy for retry."
    return 1
  fi
  if ! aws s3 cp "${storage_enc}" "s3://${S3_BUCKET}/${S3_PREFIX}/$(basename "${storage_enc}")" >>"${LOG_FILE}" 2>&1; then
    log_error "S3 upload failed for ${storage_enc}. Keeping local copy for retry."
    return 1
  fi
  log "Uploaded to s3://${S3_BUCKET}/${S3_PREFIX}/"

  # Remove local staging copies now that the upload succeeded
  shred_plaintext "${db_enc}" "${storage_enc}"

  cleanup_s3 "${RETENTION_DAYS}"

  log "---- S3 backup cycle complete (${ts}) ----"
}

# ---- Entry point ----
if [ "${1:-}" == "--once" ]; then
  run_backup_cycle
  exit $?
fi

log "backup-s3.sh started. Target: s3://${S3_BUCKET}/${S3_PREFIX}/. Interval: ${BACKUP_INTERVAL_SECONDS}s."
while true; do
  run_backup_cycle
  sleep "${BACKUP_INTERVAL_SECONDS}"
done

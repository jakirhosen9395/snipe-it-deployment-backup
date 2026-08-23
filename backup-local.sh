#!/bin/bash
# backup-local.sh
# Continuously backs up Snipe-IT (DB + storage/.env) to a LOCAL directory,
# encrypted with GPG. Interval and all paths are controlled via local.env.
#
# Run manually once to test:   sudo ./backup-local.sh --once
# Run continuously (normally done via systemd, see README Part 5):
#                               sudo ./backup-local.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/local.env"

if [ ! -f "${ENV_FILE}" ]; then
  echo "FATAL: ${ENV_FILE} not found." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "${ENV_FILE}"
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/common.sh"

require_vars DB_NAME STORAGE_DIR LOCAL_BACKUP_DIR PASSPHRASE_FILE \
  RETENTION_MINUTES BACKUP_INTERVAL_SECONDS LOG_FILE

mkdir -p "${LOCAL_BACKUP_DIR}"
touch "${LOG_FILE}"

run_backup_cycle() {
  local ts
  ts=$(date +%F_%H-%M-%S)

  local db_dump="${LOCAL_BACKUP_DIR}/snipeit_db_${ts}.sql"
  local storage_tar="${LOCAL_BACKUP_DIR}/snipeit_storage_${ts}.tar.gz"
  local db_enc="${db_dump}.gpg"
  local storage_enc="${storage_tar}.gpg"

  log "---- Starting local backup cycle (${ts}) ----"

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

  cleanup_local "${LOCAL_BACKUP_DIR}" "snipeit_*.gpg" "${RETENTION_MINUTES}"

  log "---- Local backup cycle complete (${ts}) ----"
}

# ---- Entry point ----
if [ "${1:-}" == "--once" ]; then
  run_backup_cycle
  exit $?
fi

log "backup-local.sh started. Interval: ${BACKUP_INTERVAL_SECONDS}s. Retention: ${RETENTION_MINUTES}min."
while true; do
  run_backup_cycle
  sleep "${BACKUP_INTERVAL_SECONDS}"
done

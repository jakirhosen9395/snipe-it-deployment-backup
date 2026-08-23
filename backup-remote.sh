#!/bin/bash
# backup-remote.sh
# Continuously backs up Snipe-IT (DB + storage/.env) to a REMOTE server
# over SSH/rsync, encrypted with GPG before it ever leaves this machine.
# Interval and all paths are controlled via remote.env.
#
# Run manually once to test:   sudo ./backup-remote.sh --once
# Run continuously (normally done via systemd, see README Part 5):
#                               sudo ./backup-remote.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/remote.env"

if [ ! -f "${ENV_FILE}" ]; then
  echo "FATAL: ${ENV_FILE} not found." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "${ENV_FILE}"
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/common.sh"

require_vars DB_NAME STORAGE_DIR LOCAL_STAGING_DIR PASSPHRASE_FILE \
  REMOTE_USER REMOTE_HOST REMOTE_DIR SSH_KEY RETENTION_MINUTES \
  BACKUP_INTERVAL_SECONDS LOG_FILE

mkdir -p "${LOCAL_STAGING_DIR}"
touch "${LOG_FILE}"

run_backup_cycle() {
  local ts
  ts=$(date +%F_%H-%M-%S)

  local db_dump="${LOCAL_STAGING_DIR}/snipeit_db_${ts}.sql"
  local storage_tar="${LOCAL_STAGING_DIR}/snipeit_storage_${ts}.tar.gz"
  local db_enc="${db_dump}.gpg"
  local storage_enc="${storage_tar}.gpg"

  log "---- Starting remote backup cycle (${ts}) ----"

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

  if ! rsync -avz -e "ssh -i ${SSH_KEY} -o ConnectTimeout=15" "${db_enc}" "${storage_enc}" \
      "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/" >>"${LOG_FILE}" 2>&1; then
    log_error "rsync transfer to remote server failed. Encrypted files kept locally for retry: ${db_enc}, ${storage_enc}"
    return 1
  fi
  log "Transferred to ${REMOTE_HOST}:${REMOTE_DIR}/"

  # Remove local staging copies now that the transfer succeeded
  shred_plaintext "${db_enc}" "${storage_enc}"

  cleanup_remote "snipeit_*.gpg" "${RETENTION_MINUTES}"

  log "---- Remote backup cycle complete (${ts}) ----"
}

# ---- Entry point ----
if [ "${1:-}" == "--once" ]; then
  run_backup_cycle
  exit $?
fi

log "backup-remote.sh started. Target: ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}. Interval: ${BACKUP_INTERVAL_SECONDS}s."
while true; do
  run_backup_cycle
  sleep "${BACKUP_INTERVAL_SECONDS}"
done

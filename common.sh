#!/bin/bash
# common.sh
# Shared functions used by backup-local.sh, backup-remote.sh, backup-s3.sh
# This file is sourced, not executed directly.

set -uo pipefail

# ---- Logging ----
# Requires $LOG_FILE to be set by the caller's .env
log() {
  local msg="$1"
  echo "[$(date '+%F %T')] ${msg}" | tee -a "${LOG_FILE}"
}

log_error() {
  local msg="$1"
  echo "[$(date '+%F %T')] ERROR: ${msg}" | tee -a "${LOG_FILE}" >&2
}

# ---- Core backup primitives ----

# Dump the MySQL/MariaDB database to a plain .sql file
# Usage: dump_database /path/to/output.sql
dump_database() {
  local out_file="$1"
  if ! /usr/bin/mysqldump "${DB_NAME}" > "${out_file}"; then
    log_error "mysqldump failed for database ${DB_NAME}"
    return 1
  fi
  log "Database dumped -> ${out_file} ($(du -h "${out_file}" | cut -f1))"
}

# Archive the Snipe-IT storage/ folder and .env file
# Usage: archive_storage /path/to/output.tar.gz
archive_storage() {
  local out_file="$1"
  if ! tar -czf "${out_file}" -C "${STORAGE_DIR}" storage .env; then
    log_error "tar failed for storage directory ${STORAGE_DIR}"
    return 1
  fi
  log "Storage archived -> ${out_file} ($(du -h "${out_file}" | cut -f1))"
}

# Encrypt a file with GPG symmetric AES256, using the shared passphrase file
# Usage: encrypt_file /path/to/plain.file /path/to/output.gpg
encrypt_file() {
  local in_file="$1"
  local out_file="$2"
  if ! gpg --batch --yes --passphrase-file "${PASSPHRASE_FILE}" \
      --symmetric --cipher-algo AES256 -o "${out_file}" "${in_file}"; then
    log_error "GPG encryption failed for ${in_file}"
    return 1
  fi
  log "Encrypted -> ${out_file}"
}

# Decrypt a GPG file back to plaintext
# Usage: decrypt_file /path/to/input.gpg /path/to/output.file
decrypt_file() {
  local in_file="$1"
  local out_file="$2"
  if ! gpg --batch --yes --passphrase-file "${PASSPHRASE_FILE}" \
      --decrypt -o "${out_file}" "${in_file}"; then
    log_error "GPG decryption failed for ${in_file}"
    return 1
  fi
  log "Decrypted -> ${out_file}"
}

# Delete plaintext files immediately after encryption (never leave plaintext on disk)
# Usage: shred_plaintext file1 file2 ...
shred_plaintext() {
  for f in "$@"; do
    if [ -f "$f" ]; then
      rm -f "$f"
      log "Removed plaintext: $f"
    fi
  done
}

# Delete local files older than N minutes matching a pattern
# Usage: cleanup_local /dir "pattern*" 1440
cleanup_local() {
  local dir="$1"
  local pattern="$2"
  local minutes="$3"
  find "${dir}" -maxdepth 1 -name "${pattern}" -mmin "+${minutes}" -print -delete | while read -r f; do
    log "Deleted old local backup: $f"
  done
}

# Delete remote files (over SSH) older than N minutes matching a pattern
# Usage: cleanup_remote "pattern*" 10080
cleanup_remote() {
  local pattern="$1"
  local minutes="$2"
  ssh -i "${SSH_KEY}" "${REMOTE_USER}@${REMOTE_HOST}" \
    "find ${REMOTE_DIR} -maxdepth 1 -name '${pattern}' -mmin +${minutes} -print -delete" \
    | while read -r f; do
      log "Deleted old remote backup: $f"
    done
}

# Delete S3 objects older than N days under a prefix
# Usage: cleanup_s3 30
cleanup_s3() {
  local days="$1"
  local cutoff
  cutoff=$(date -d "-${days} days" +%s 2>/dev/null || date -v-"${days}"d +%s)

  aws s3api list-objects-v2 \
    --bucket "${S3_BUCKET}" \
    --prefix "${S3_PREFIX}/" \
    --query "Contents[].{Key:Key,LastModified:LastModified}" \
    --output text 2>>"${LOG_FILE}" | while read -r key last_modified; do
      [ -z "${key:-}" ] && continue
      obj_epoch=$(date -d "${last_modified}" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${last_modified%%.*}" +%s 2>/dev/null)
      if [ -n "${obj_epoch:-}" ] && [ "${obj_epoch}" -lt "${cutoff}" ]; then
        aws s3 rm "s3://${S3_BUCKET}/${key}" >>"${LOG_FILE}" 2>&1
        log "Deleted old S3 object: ${key}"
      fi
    done
}

# Sanity check: make sure all required variables from the .env are actually set
require_vars() {
  for var_name in "$@"; do
    if [ -z "${!var_name:-}" ]; then
      echo "FATAL: required variable '${var_name}' is not set in the .env file. Aborting." >&2
      exit 1
    fi
  done
}

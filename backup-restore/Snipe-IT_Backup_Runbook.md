# Snipe-IT Backup Runbook

## Full Disaster-Recovery Backup --- v8.7.2 / build 24589

This document creates a recovery backup containing the Snipe-IT
database, environment configuration, application configuration/version
evidence, public uploads, private uploads, OAuth keys, checksums, and
system information.

### 0. Critical rules

-   Run backup commands as `root`.
-   Do not print or paste `APP_KEY`, `DB_PASSWORD`, OAuth private keys,
    or other secrets.
-   Keep the ZIP and its checksum together.
-   Store at least one copy outside the server.
-   Test the ZIP and checksum before considering the backup valid.
-   A backup is not proven until it has been successfully restored on
    another VM.

### 1. Variables

Set the backup timestamp once:

``` bash
BACKUP_NAME="snipeit-full-backup-$(date +%Y-%m-%d_%H-%M-%S)"
BACKUP_DIR="/root/$BACKUP_NAME"
SNIPE_DIR="/var/www/html/snipe-it"

echo "BACKUP_NAME=$BACKUP_NAME"
echo "BACKUP_DIR=$BACKUP_DIR"
```

### 2. Verify the running installation

``` bash
test -d "$SNIPE_DIR" || { echo "ERROR: Snipe-IT directory not found"; exit 1; }
test -f "$SNIPE_DIR/.env" || { echo "ERROR: .env not found"; exit 1; }
test -f "$SNIPE_DIR/artisan" || { echo "ERROR: artisan not found"; exit 1; }
test -f "$SNIPE_DIR/composer.lock" || { echo "ERROR: composer.lock not found"; exit 1; }
```

Check services:

``` bash
systemctl is-active --quiet mariadb || { echo "ERROR: MariaDB is not running"; exit 1; }
systemctl is-active --quiet php8.3-fpm || { echo "ERROR: PHP-FPM is not running"; exit 1; }
systemctl is-active --quiet nginx || { echo "ERROR: Nginx is not running"; exit 1; }
```

Check versions:

``` bash
php -v | head -1
mariadb --version
cd "$SNIPE_DIR"
git log -1 --oneline
git describe --tags --always
```

For the original installation, expected Snipe-IT identity:

``` text
v8.7.2
build 24589
commit gf0bd1f8d76
PHP 8.3.33
Laravel 12.68.0
MariaDB 11.8.6
```

### 3. Create backup directory

``` bash
mkdir -p "$BACKUP_DIR"/{database,config,storage,storage/public_uploads,storage/private_uploads,storage/oauth}
chmod 700 "$BACKUP_DIR"
```

### 4. Back up the database

Check database settings without printing the password:

``` bash
grep -E '^(DB_CONNECTION|DB_HOST|DB_PORT|DB_DATABASE|DB_USERNAME)=' "$SNIPE_DIR/.env"
```

Load only the required non-secret values:

``` bash
DB_DATABASE=$(grep '^DB_DATABASE=' "$SNIPE_DIR/.env" | cut -d= -f2-)
DB_USERNAME=$(grep '^DB_USERNAME=' "$SNIPE_DIR/.env" | cut -d= -f2-)
```

Confirm:

``` bash
echo "Database: $DB_DATABASE"
echo "User: $DB_USERNAME"
```

For this installation:

``` text
Database: snipeit_db
User: snipeit_user
```

Create the SQL dump:

``` bash
mariadb-dump \
  --single-transaction \
  --routines \
  --triggers \
  --events \
  "$DB_DATABASE" \
  > "$BACKUP_DIR/database/snipeit.sql"
```

Verify:

``` bash
ls -lh "$BACKUP_DIR/database/snipeit.sql"
test -s "$BACKUP_DIR/database/snipeit.sql" || { echo "ERROR: SQL dump is empty"; exit 1; }
```

Count tables in the dump:

``` bash
grep -c '^CREATE TABLE' "$BACKUP_DIR/database/snipeit.sql"
```

For the original backup this was:

``` text
59
```

### 5. Back up the original .env

``` bash
cp "$SNIPE_DIR/.env" "$BACKUP_DIR/config/.env"
chmod 600 "$BACKUP_DIR/config/.env"
```

Verify it exists without printing secrets:

``` bash
ls -l "$BACKUP_DIR/config/.env"
grep -E '^(APP_ENV|APP_URL|APP_TIMEZONE|DB_CONNECTION|DB_HOST|DB_PORT|DB_DATABASE|DB_USERNAME|PRIVATE_FILESYSTEM_DISK|PUBLIC_FILESYSTEM_DISK)=' "$BACKUP_DIR/config/.env"
grep '^APP_KEY=' "$BACKUP_DIR/config/.env" | sed 's/=.*/=********/'
```

### 6. Back up application configuration/version evidence

Create a configuration archive while excluding secrets and generated
dependencies:

``` bash
cd "$SNIPE_DIR"

tar -czf "$BACKUP_DIR/config/snipeit-config.tar.gz" \
  --exclude='.env' \
  --exclude='vendor' \
  --exclude='node_modules' \
  --exclude='storage/logs' \
  config \
  composer.json \
  composer.lock \
  package.json \
  package-lock.json \
  artisan
```

Verify:

``` bash
tar -tzf "$BACKUP_DIR/config/snipeit-config.tar.gz" | head -100
```

Record exact version/commit:

``` bash
{
  echo "Snipe-IT Git:"
  git log -1 --format='commit=%H'
  git describe --tags --always
  echo
  echo "Snipe-IT version.php:"
  grep -E "app_version|full_app_version|build_version|hash_version" config/version.php
  echo
  echo "PHP:"
  php -v | head -1
  echo
  echo "Laravel:"
  sudo -u www-data php artisan --version 2>/dev/null || true
  echo
  echo "MariaDB:"
  mariadb --version
} > "$BACKUP_DIR/system-info.txt"
```

Review:

``` bash
cat "$BACKUP_DIR/system-info.txt"
```

### 7. Back up public uploads

The original installation used:

``` text
/var/www/html/snipe-it/public/uploads
```

Copy them:

``` bash
if [ -d "$SNIPE_DIR/public/uploads" ]; then
    cp -a "$SNIPE_DIR/public/uploads/." "$BACKUP_DIR/storage/public_uploads/"
else
    echo "WARNING: public/uploads does not exist"
fi
```

Verify:

``` bash
du -sh "$BACKUP_DIR/storage/public_uploads"
find "$BACKUP_DIR/storage/public_uploads" -type f | wc -l
```

### 8. Back up private uploads

``` bash
if [ -d "$SNIPE_DIR/storage/private_uploads" ]; then
    cp -a "$SNIPE_DIR/storage/private_uploads/." "$BACKUP_DIR/storage/private_uploads/"
else
    echo "WARNING: storage/private_uploads does not exist"
fi
```

Verify:

``` bash
du -sh "$BACKUP_DIR/storage/private_uploads"
find "$BACKUP_DIR/storage/private_uploads" -type f | wc -l
```

### 9. Back up OAuth keys

Check:

``` bash
ls -l \
  "$SNIPE_DIR/storage/oauth-private.key" \
  "$SNIPE_DIR/storage/oauth-public.key"
```

Copy:

``` bash
cp "$SNIPE_DIR/storage/oauth-private.key" "$BACKUP_DIR/storage/oauth/"
cp "$SNIPE_DIR/storage/oauth-public.key" "$BACKUP_DIR/storage/oauth/"
```

Protect them:

``` bash
chmod 600 "$BACKUP_DIR/storage/oauth/oauth-private.key"
chmod 644 "$BACKUP_DIR/storage/oauth/oauth-public.key"
```

Verify without displaying contents:

``` bash
ls -l "$BACKUP_DIR/storage/oauth/"
```

### 10. Verify backup structure

``` bash
cd "$BACKUP_DIR"

find . -maxdepth 3 -type f -print | sort
```

Expected important files/directories:

``` text
./config/.env
./config/snipeit-config.tar.gz
./database/snipeit.sql
./storage/oauth/oauth-private.key
./storage/oauth/oauth-public.key
./storage/public_uploads/
./storage/private_uploads/
./system-info.txt
```

### 11. Generate SHA256 manifest

Run this after all backup files have been copied:

``` bash
cd "$BACKUP_DIR"

rm -f SHA256SUMS

find . -type f ! -name 'SHA256SUMS' -print0 \
  | sort -z \
  | xargs -0 sha256sum \
  > SHA256SUMS
```

Check it:

``` bash
cat SHA256SUMS
```

### 12. Verify every backup file

``` bash
cd "$BACKUP_DIR"

sha256sum -c SHA256SUMS
```

Every entry must say:

``` text
OK
```

If anything says `FAILED`, stop and fix the backup before creating the
final ZIP.

### 13. Create the recovery ZIP

``` bash
cd /root

zip -r -9 \
  "${BACKUP_NAME}.zip" \
  "$BACKUP_NAME"
```

Verify ZIP exists:

``` bash
ls -lh "/root/${BACKUP_NAME}.zip"
```

### 14. Test the ZIP

``` bash
unzip -t "/root/${BACKUP_NAME}.zip"
```

Expected:

``` text
No errors detected in compressed data
```

### 15. Create ZIP checksum

``` bash
cd /root

sha256sum "${BACKUP_NAME}.zip" \
  > "${BACKUP_NAME}.zip.sha256"
```

Display:

``` bash
cat "/root/${BACKUP_NAME}.zip.sha256"
```

### 16. Verify the ZIP checksum

``` bash
cd /root

sha256sum -c "${BACKUP_NAME}.zip.sha256"
```

Expected:

``` text
<backup-name>.zip: OK
```

### 17. Verify the archive can be extracted

Use a temporary directory:

``` bash
TEST_DIR="/tmp/snipeit-backup-test-$(date +%s)"

mkdir -p "$TEST_DIR"

unzip -q \
  "/root/${BACKUP_NAME}.zip" \
  -d "$TEST_DIR"
```

Verify:

``` bash
find "$TEST_DIR/$BACKUP_NAME" -maxdepth 3 -type f | sort
```

Verify the SQL exists and is non-empty:

``` bash
test -s "$TEST_DIR/$BACKUP_NAME/database/snipeit.sql" \
  && echo "SQL backup OK"
```

Verify `.env`:

``` bash
test -s "$TEST_DIR/$BACKUP_NAME/config/.env" \
  && echo ".env backup OK"
```

Verify configuration archive:

``` bash
test -s "$TEST_DIR/$BACKUP_NAME/config/snipeit-config.tar.gz" \
  && echo "config archive OK"
```

Remove the test extraction:

``` bash
rm -rf "$TEST_DIR"
```

### 18. Final backup inventory

``` bash
echo "========== BACKUP =========="
echo "Name: $BACKUP_NAME"
echo "Directory: $BACKUP_DIR"
echo
echo "Files:"
find "$BACKUP_DIR" -type f | sort
echo
echo "Sizes:"
du -sh "$BACKUP_DIR"
ls -lh "/root/${BACKUP_NAME}.zip" "/root/${BACKUP_NAME}.zip.sha256"
echo
echo "ZIP SHA256:"
cat "/root/${BACKUP_NAME}.zip.sha256"
echo
echo "========== END =========="
```

### 19. Copy the backup OFF the server

At minimum, copy these two files to another machine/storage:

``` text
/root/snipeit-full-backup-YYYY-MM-DD_HH-MM-SS.zip
/root/snipeit-full-backup-YYYY-MM-DD_HH-MM-SS.zip.sha256
```

Example from your workstation:

``` bash
scp root@OLD_SERVER_IP:/root/snipeit-full-backup-YYYY-MM-DD_HH-MM-SS.zip .
scp root@OLD_SERVER_IP:/root/snipeit-full-backup-YYYY-MM-DD_HH-MM-SS.zip.sha256 .
```

Then verify on the destination:

``` bash
sha256sum -c snipeit-full-backup-YYYY-MM-DD_HH-MM-SS.zip.sha256
```

### 20. Restore-test requirement

Do not call a backup "disaster-recovery ready" until the ZIP has been
restored successfully on a separate VM.

The restore test must verify:

``` text
Checksum
ZIP integrity
Exact Snipe-IT version
Original APP_KEY
Database
Users
Assets
Models
Companies
Locations
Public uploads
Private uploads
OAuth keys
Web login
Asset assignment/history
```

### 21. Secret handling

The backup contains highly sensitive material, especially:

``` text
config/.env
storage/oauth/oauth-private.key
database/snipeit.sql
```

Protect the ZIP as a secret.

Do not:

``` text
commit it to Git
upload it to a public file host
paste its contents into chat
put .env into a public repository
```

If an `APP_KEY`, database password, or OAuth private key is ever
exposed, plan a controlled secret rotation after recovery validation. Do
not casually regenerate `APP_KEY` during a restoration because existing
encrypted data may depend on it.

# Snipe-IT Disaster Recovery Restore Runbook

## Restore from `snipeit-full-backup-YYYY-MM-DD_HH-MM-SS.zip`

This procedure restores an existing Snipe-IT installation to a new
Debian 13 VM from the custom full backup described in the companion
Backup Runbook.

**Known original installation:** - Snipe-IT: **v8.7.2** - Build:
**24589** - Git commit: **gf0bd1f8d76** - Laravel: **12.68.0** - PHP:
**8.3.33** - MariaDB: **11.8.6** - Application path:
`/var/www/html/snipe-it` - Database: `snipeit_db` - Database user:
`snipeit_user`

------------------------------------------------------------------------

# 0. CRITICAL RESTORE RULES

This is a **RESTORATION**, not a fresh Snipe-IT installation.

Never run these during the initial restore:

``` bash
php artisan key:generate
php artisan migrate:fresh
php artisan migrate:refresh
php artisan migrate
```

Do not click:

``` text
/setup → Create database tables
```

The existing database is restored from the SQL dump.

The original `APP_KEY` must be preserved.

------------------------------------------------------------------------

# 1. Prepare the new VM

Recommended minimum:

``` text
Debian 13
2 vCPU
4 GB RAM
30 GB+ disk
Static/reserved IP
SSH access
```

Log in:

``` bash
ssh root@NEW_SERVER_IP
```

Verify:

``` bash
cat /etc/os-release
uname -a
whoami
```

Update:

``` bash
apt update
apt upgrade -y
```

If a reboot is required:

``` bash
reboot
```

Reconnect.

------------------------------------------------------------------------

# 2. Install required base packages

``` bash
apt update

apt install -y \
  ca-certificates \
  apt-transport-https \
  curl \
  wget \
  gnupg \
  unzip \
  zip \
  git \
  tree \
  graphviz \
  mariadb-client \
  openssl \
  ufw
```

Verify:

``` bash
git --version
unzip -v | head -1
mariadb --version
openssl version
```

------------------------------------------------------------------------

# 3. Put the backup on the new VM

Place these together:

``` text
snipeit-full-backup-YYYY-MM-DD_HH-MM-SS.zip
snipeit-full-backup-YYYY-MM-DD_HH-MM-SS.zip.sha256
```

Example location:

``` text
/home/jakirhosen9395/
```

Verify:

``` bash
ls -lh \
  /home/jakirhosen9395/snipeit-full-backup-YYYY-MM-DD_HH-MM-SS.zip \
  /home/jakirhosen9395/snipeit-full-backup-YYYY-MM-DD_HH-MM-SS.zip.sha256
```

------------------------------------------------------------------------

# 4. Verify the ZIP checksum BEFORE extraction

``` bash
cd /home/jakirhosen9395

sha256sum -c \
  snipeit-full-backup-YYYY-MM-DD_HH-MM-SS.zip.sha256
```

Expected:

``` text
snipeit-full-backup-YYYY-MM-DD_HH-MM-SS.zip: OK
```

If it says `FAILED`, STOP.

------------------------------------------------------------------------

# 5. Test ZIP integrity

``` bash
unzip -t \
  /home/jakirhosen9395/snipeit-full-backup-YYYY-MM-DD_HH-MM-SS.zip
```

Expected:

``` text
No errors detected in compressed data
```

If the test fails, STOP.

------------------------------------------------------------------------

# 6. Extract the backup

``` bash
mkdir -p /root/snipeit-restore

unzip \
  /home/jakirhosen9395/snipeit-full-backup-YYYY-MM-DD_HH-MM-SS.zip \
  -d /root/snipeit-restore
```

Set the backup variable:

``` bash
export BACKUP_DIR="/root/snipeit-restore/snipeit-full-backup-YYYY-MM-DD_HH-MM-SS"
```

Verify:

``` bash
ls -lah "$BACKUP_DIR"
find "$BACKUP_DIR" -maxdepth 3 -type f | sort
```

------------------------------------------------------------------------

# 7. Verify every extracted backup file

``` bash
cd "$BACKUP_DIR"

sha256sum -c SHA256SUMS
```

Every file must say:

``` text
OK
```

Stop if anything fails.

------------------------------------------------------------------------

# 8. Install PHP 8.3

Install repository prerequisites:

``` bash
apt install -y \
  ca-certificates \
  apt-transport-https \
  curl \
  gnupg
```

Install Sury keyring:

``` bash
curl -sSLo /tmp/debsuryorg-archive-keyring.deb \
  https://packages.sury.org/debsuryorg-archive-keyring.deb

dpkg -i /tmp/debsuryorg-archive-keyring.deb
```

Add the Debian PHP repository:

``` bash
sh -c 'echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list'
```

Update:

``` bash
apt update
```

Install PHP:

``` bash
apt install -y \
  php8.3 \
  php8.3-cli \
  php8.3-fpm \
  php8.3-common \
  php8.3-mysql \
  php8.3-gd \
  php8.3-bcmath \
  php8.3-mbstring \
  php8.3-xml \
  php8.3-curl \
  php8.3-zip \
  php8.3-intl \
  php8.3-ldap \
  php8.3-soap \
  php8.3-bz2 \
  php8.3-opcache \
  php8.3-readline
```

Verify:

``` bash
php -v
php-fpm8.3 -v
```

Enable PHP-FPM:

``` bash
systemctl enable --now php8.3-fpm
systemctl status php8.3-fpm --no-pager
```

------------------------------------------------------------------------

# 9. Install MariaDB and Nginx

``` bash
apt install -y \
  mariadb-server \
  nginx
```

Enable:

``` bash
systemctl enable --now mariadb
systemctl enable --now nginx
```

Verify:

``` bash
systemctl status mariadb --no-pager
systemctl status nginx --no-pager
systemctl status php8.3-fpm --no-pager
```

Test MariaDB:

``` bash
mariadb -u root -e "SELECT VERSION();"
```

------------------------------------------------------------------------

# 10. Install Composer

``` bash
cd /tmp

curl -sS https://getcomposer.org/installer | php

mv composer.phar /usr/local/bin/composer
chmod 755 /usr/local/bin/composer
```

Verify:

``` bash
composer --version
```

------------------------------------------------------------------------

# 11. Create Snipe-IT directory

``` bash
mkdir -p /var/www/html
```

------------------------------------------------------------------------

# 12. Clone the Snipe-IT source

``` bash
cd /var/www/html

git clone \
  https://github.com/grokability/snipe-it.git \
  snipe-it
```

Enter:

``` bash
cd /var/www/html/snipe-it
```

------------------------------------------------------------------------

# 13. Fetch and checkout the EXACT original commit

The original installation was:

``` text
v8.7.2
build 24589
commit gf0bd1f8d76
```

Mark the directory safe for Git:

``` bash
git config --global --add safe.directory /var/www/html/snipe-it
```

Fetch the exact commit:

``` bash
git fetch --depth=1 origin gf0bd1f8d76
```

Checkout:

``` bash
git checkout gf0bd1f8d76
```

Verify:

``` bash
git log -1 --oneline
git describe --tags --always
```

Verify version:

``` bash
grep -E \
"app_version|full_app_version|build_version|hash_version" \
config/version.php
```

Do not continue if the source is not the expected version/commit.

------------------------------------------------------------------------

# 14. Install Composer dependencies

Set ownership:

``` bash
chown -R www-data:www-data /var/www/html/snipe-it
```

Install from the lock file:

``` bash
cd /var/www/html/snipe-it

sudo -u www-data composer install \
  --no-dev \
  --prefer-dist \
  --optimize-autoloader
```

IMPORTANT:

Do not use:

``` bash
composer update
```

Verify:

``` bash
test -f vendor/autoload.php \
  && echo "Composer dependencies OK"
```

------------------------------------------------------------------------

# 15. Restore the original `.env`

Copy:

``` bash
cp \
  "$BACKUP_DIR/config/.env" \
  /var/www/html/snipe-it/.env
```

Set permissions:

``` bash
chown www-data:www-data /var/www/html/snipe-it/.env
chmod 640 /var/www/html/snipe-it/.env
```

Verify configuration without exposing secrets:

``` bash
grep -E \
'^(APP_ENV|APP_URL|APP_TIMEZONE|DB_CONNECTION|DB_HOST|DB_PORT|DB_DATABASE|DB_USERNAME|PRIVATE_FILESYSTEM_DISK|PUBLIC_FILESYSTEM_DISK)=' \
/var/www/html/snipe-it/.env
```

Verify APP_KEY exists without displaying it:

``` bash
grep '^APP_KEY=' /var/www/html/snipe-it/.env \
  | sed 's/=.*/=********/'
```

Expected:

``` text
APP_KEY=********
```

NEVER run:

``` bash
php artisan key:generate
```

------------------------------------------------------------------------

# 16. Set the new server URL

Edit:

``` bash
nano /var/www/html/snipe-it/.env
```

Change only environment-specific values.

Example:

``` text
APP_ENV=production
APP_URL=http://NEW_SERVER_IP
APP_TIMEZONE='Asia/Dhaka'

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=snipeit_db
DB_USERNAME=snipeit_user
```

Keep the original:

``` text
APP_KEY
PRIVATE_FILESYSTEM_DISK
PUBLIC_FILESYSTEM_DISK
```

Do not put the actual secret values in this document.

------------------------------------------------------------------------

# 17. Create the empty database and database user

Generate a new database password:

``` bash
DBPASS=$(openssl rand -hex 24)
```

Create the database/user:

``` bash
mariadb -u root <<SQL
CREATE DATABASE IF NOT EXISTS snipeit_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'snipeit_user'@'localhost'
  IDENTIFIED BY '${DBPASS}';

ALTER USER 'snipeit_user'@'localhost'
  IDENTIFIED BY '${DBPASS}';

GRANT ALL PRIVILEGES
  ON snipeit_db.*
  TO 'snipeit_user'@'localhost';

FLUSH PRIVILEGES;
SQL
```

Update `.env` with exactly the same password:

``` bash
sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=$DBPASS|" \
  /var/www/html/snipe-it/.env
```

Secure `.env`:

``` bash
chown www-data:www-data /var/www/html/snipe-it/.env
chmod 640 /var/www/html/snipe-it/.env
```

------------------------------------------------------------------------

# 18. TEST DATABASE CONNECTION BEFORE IMPORT

Do not use an interactive `-p` prompt if you are unsure of the password.

Test:

``` bash
mariadb \
  -u snipeit_user \
  -p"$DBPASS" \
  snipeit_db \
  -e "SELECT 2+2 AS result;"
```

Expected:

``` text
result
4
```

If this fails, STOP.

Do not import until this succeeds.

Keep `DBPASS` in the current shell for the following database
operations.

------------------------------------------------------------------------

# 19. Confirm the new database is empty

``` bash
mariadb \
  -u snipeit_user \
  -p"$DBPASS" \
  snipeit_db \
  -e "SHOW TABLES;"
```

It should return no Snipe-IT tables.

Do not run migrations.

------------------------------------------------------------------------

# 20. Verify SQL backup

``` bash
ls -lh "$BACKUP_DIR/database/snipeit.sql"
```

Count tables in the SQL:

``` bash
grep -c '^CREATE TABLE' \
  "$BACKUP_DIR/database/snipeit.sql"
```

For the original backup:

``` text
59
```

------------------------------------------------------------------------

# 21. IMPORT THE DATABASE

This is the authoritative database restore:

``` bash
mariadb \
  -u snipeit_user \
  -p"$DBPASS" \
  snipeit_db \
  < "$BACKUP_DIR/database/snipeit.sql"
```

If any SQL error is printed, STOP.

Do not run another import until the cause is understood.

------------------------------------------------------------------------

# 22. Verify database table count

``` bash
mariadb \
  -u snipeit_user \
  -p"$DBPASS" \
  snipeit_db \
  -N \
  -e "SHOW TABLES;" | wc -l
```

For this backup:

``` text
59
```

------------------------------------------------------------------------

# 23. Verify critical tables

``` bash
mariadb \
  -u snipeit_user \
  -p"$DBPASS" \
  snipeit_db \
  -e "
SHOW TABLES LIKE 'users';
SHOW TABLES LIKE 'assets';
SHOW TABLES LIKE 'models';
SHOW TABLES LIKE 'companies';
SHOW TABLES LIKE 'locations';
"
```

All should exist.

------------------------------------------------------------------------

# 24. Verify restored data

``` bash
mariadb \
  -u snipeit_user \
  -p"$DBPASS" \
  snipeit_db \
  -e "
SELECT COUNT(*) AS users FROM users;
SELECT COUNT(*) AS assets FROM assets;
SELECT COUNT(*) AS models FROM models;
SELECT COUNT(*) AS companies FROM companies;
SELECT COUNT(*) AS locations FROM locations;
"
```

Record these numbers for future comparison.

------------------------------------------------------------------------

# 25. Verify migrations --- DO NOT MODIFY THEM

``` bash
mariadb \
  -u snipeit_user \
  -p"$DBPASS" \
  snipeit_db \
  -e "
SELECT MAX(id) AS max_migration_id,
       COUNT(*) AS migration_count
FROM migrations;
"
```

Latest entries:

``` bash
mariadb \
  -u snipeit_user \
  -p"$DBPASS" \
  snipeit_db \
  -e "
SELECT id, migration, batch
FROM migrations
ORDER BY id DESC
LIMIT 20;
"
```

Do not run migrations just because the migration table exists.

------------------------------------------------------------------------

# 26. Restore public uploads

The custom backup stores the original:

``` text
public/uploads/
```

inside:

``` text
storage/public_uploads/
```

Create destination:

``` bash
mkdir -p /var/www/html/snipe-it/public/uploads
```

Restore:

``` bash
cp -a \
  "$BACKUP_DIR/storage/public_uploads/." \
  /var/www/html/snipe-it/public/uploads/
```

Verify:

``` bash
find /var/www/html/snipe-it/public/uploads \
  -type f | wc -l
```

------------------------------------------------------------------------

# 27. Restore private uploads

``` bash
mkdir -p /var/www/html/snipe-it/storage/private_uploads
```

Restore:

``` bash
cp -a \
  "$BACKUP_DIR/storage/private_uploads/." \
  /var/www/html/snipe-it/storage/private_uploads/
```

Verify:

``` bash
find /var/www/html/snipe-it/storage/private_uploads \
  -type f | wc -l
```

------------------------------------------------------------------------

# 28. Restore OAuth keys

Copy:

``` bash
cp \
  "$BACKUP_DIR/storage/oauth/oauth-private.key" \
  /var/www/html/snipe-it/storage/oauth-private.key

cp \
  "$BACKUP_DIR/storage/oauth/oauth-public.key" \
  /var/www/html/snipe-it/storage/oauth-public.key
```

Ownership:

``` bash
chown www-data:www-data \
  /var/www/html/snipe-it/storage/oauth-private.key \
  /var/www/html/snipe-it/storage/oauth-public.key
```

Permissions:

``` bash
chmod 600 \
  /var/www/html/snipe-it/storage/oauth-private.key

chmod 644 \
  /var/www/html/snipe-it/storage/oauth-public.key
```

Verify:

``` bash
ls -l \
  /var/www/html/snipe-it/storage/oauth-private.key \
  /var/www/html/snipe-it/storage/oauth-public.key
```

------------------------------------------------------------------------

# 29. Set application permissions

Ownership:

``` bash
chown -R www-data:www-data /var/www/html/snipe-it
```

Directories:

``` bash
find /var/www/html/snipe-it \
  -type d \
  -exec chmod 755 {} \;
```

Files:

``` bash
find /var/www/html/snipe-it \
  -type f \
  -exec chmod 644 {} \;
```

Writable directories:

``` bash
chmod -R 775 /var/www/html/snipe-it/storage
chmod -R 775 /var/www/html/snipe-it/public/uploads
chmod -R 775 /var/www/html/snipe-it/bootstrap/cache
```

Restore sensitive permissions:

``` bash
chmod 600 /var/www/html/snipe-it/storage/oauth-private.key
chmod 644 /var/www/html/snipe-it/storage/oauth-public.key
chmod 640 /var/www/html/snipe-it/.env
```

------------------------------------------------------------------------

# 30. Configure Nginx

Create:

``` bash
nano /etc/nginx/sites-available/snipeit
```

Use:

``` nginx
server {
    listen 80;
    listen [::]:80;

    server_name NEW_SERVER_IP;

    root /var/www/html/snipe-it/public;
    index index.php index.html;

    client_max_body_size 100M;

    location / {
        try_files $uri $uri/ /index.php$is_args$args;
    }

    location ~ \.php$ {
        try_files $uri =404;

        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT $document_root;

        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
```

Replace:

``` text
NEW_SERVER_IP
```

with the real IP or DNS name.

Enable:

``` bash
ln -s \
  /etc/nginx/sites-available/snipeit \
  /etc/nginx/sites-enabled/snipeit
```

Disable default site:

``` bash
rm -f /etc/nginx/sites-enabled/default
```

Test:

``` bash
nginx -t
```

Only continue if:

``` text
syntax is ok
test is successful
```

------------------------------------------------------------------------

# 31. Restart services

``` bash
systemctl restart mariadb
systemctl restart php8.3-fpm
systemctl restart nginx
```

Verify:

``` bash
systemctl is-active mariadb
systemctl is-active php8.3-fpm
systemctl is-active nginx
```

All should output:

``` text
active
```

------------------------------------------------------------------------

# 32. Clear Laravel cache

``` bash
cd /var/www/html/snipe-it

sudo -u www-data php artisan optimize:clear
```

Then:

``` bash
sudo -u www-data php artisan config:cache
```

Do not generate a new key.

------------------------------------------------------------------------

# 33. Database test again after cache

``` bash
mariadb \
  -u snipeit_user \
  -p"$DBPASS" \
  snipeit_db \
  -e "SELECT 2+2 AS result;"
```

Expected:

``` text
4
```

Now the password variable can be removed:

``` bash
unset DBPASS
```

------------------------------------------------------------------------

# 34. Test HTTP

Replace the IP:

``` bash
curl -I http://NEW_SERVER_IP/
```

Also:

``` bash
curl -s http://NEW_SERVER_IP/ | head -30
```

------------------------------------------------------------------------

# 35. DO NOT open /setup for database creation

Do not perform:

``` text
/setup → Create database tables
```

This is an existing restored installation.

Use:

``` text
http://NEW_SERVER_IP/
```

------------------------------------------------------------------------

# 36. Login and validate the application

Use an existing user from the restored database.

Verify:

``` text
Users
Assets
Asset checkout information
Asset history
Models
Companies
Locations
Categories
Suppliers
Manufacturers
Attachments/images
```

Pay particular attention to assets that were already assigned before the
disaster.

------------------------------------------------------------------------

# 37. Verify public uploads

Open records with images:

``` text
Assets
Users
Models
Companies
Locations
```

If images fail, check:

``` bash
ls -lah /var/www/html/snipe-it/public/uploads
```

and:

``` bash
find /var/www/html/snipe-it/public/uploads \
  -type f | wc -l
```

------------------------------------------------------------------------

# 38. Verify private uploads

Check:

``` bash
ls -lah /var/www/html/snipe-it/storage/private_uploads
```

Check permissions:

``` bash
namei -l /var/www/html/snipe-it/storage/private_uploads
```

------------------------------------------------------------------------

# 39. Verify OAuth keys

``` bash
ls -l \
  /var/www/html/snipe-it/storage/oauth-private.key \
  /var/www/html/snipe-it/storage/oauth-public.key
```

Expected:

``` text
oauth-private.key  600  www-data:www-data
oauth-public.key   644  www-data:www-data
```

------------------------------------------------------------------------

# 40. Troubleshooting: database access denied

If you see:

``` text
SQLSTATE[HY000] [1045] Access denied
```

Do not repeatedly guess passwords.

Load the `.env` password:

``` bash
cd /var/www/html/snipe-it

DBPASS=$(grep '^DB_PASSWORD=' .env | cut -d= -f2-)
```

Test:

``` bash
mariadb \
  -u snipeit_user \
  -p"$DBPASS" \
  snipeit_db \
  -e "SELECT 2+2 AS result;"
```

If it succeeds:

``` text
4
```

the credentials are correct.

If it fails, reset the database password:

``` bash
DBPASS=$(openssl rand -hex 24)

mariadb -u root -e "
ALTER USER 'snipeit_user'@'localhost'
IDENTIFIED BY '$DBPASS';
FLUSH PRIVILEGES;
"

sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=$DBPASS|" \
  /var/www/html/snipe-it/.env
```

Test again:

``` bash
mariadb \
  -u snipeit_user \
  -p"$DBPASS" \
  snipeit_db \
  -e "SELECT 2+2 AS result;"
```

------------------------------------------------------------------------

# 41. Troubleshooting: PsySH/Tinker permission error

If:

``` bash
sudo -u www-data php artisan tinker ...
```

reports:

``` text
Writing to directory /var/www/.config/psysh is not allowed.
```

This is not proof of a database failure.

Create the directory:

``` bash
install -d \
  -o www-data \
  -g www-data \
  -m 700 \
  /var/www/.config
```

Then:

``` bash
sudo -u www-data php artisan tinker \
  --execute="DB::select('SELECT 2+2 AS result');"
```

Alternatively, test the database directly with MariaDB, which is the
preferred recovery test:

``` bash
DBPASS=$(grep '^DB_PASSWORD=' /var/www/html/snipe-it/.env | cut -d= -f2-)

mariadb \
  -u snipeit_user \
  -p"$DBPASS" \
  snipeit_db \
  -e "SELECT 2+2 AS result;"

unset DBPASS
```

------------------------------------------------------------------------

# 42. Troubleshooting: blank page / HTTP 500

Check Snipe-IT log:

``` bash
tail -100 /var/www/html/snipe-it/storage/logs/laravel.log
```

Check Nginx:

``` bash
journalctl -u nginx -n 100 --no-pager
```

Check PHP-FPM:

``` bash
journalctl -u php8.3-fpm -n 100 --no-pager
```

Check Nginx configuration:

``` bash
nginx -t
```

Check permissions:

``` bash
namei -l /var/www/html/snipe-it/public/index.php
```

------------------------------------------------------------------------

# 43. Troubleshooting: Composer/vendor problem

Verify:

``` bash
test -f /var/www/html/snipe-it/vendor/autoload.php \
  && echo "vendor OK"
```

If missing:

``` bash
cd /var/www/html/snipe-it

chown -R www-data:www-data /var/www/html/snipe-it

sudo -u www-data composer install \
  --no-dev \
  --prefer-dist \
  --optimize-autoloader
```

Never run `composer update` during disaster recovery.

------------------------------------------------------------------------

# 44. Troubleshooting: database import interrupted

If you are unsure whether the SQL import completed, do not blindly
import over the partially restored database.

First verify:

``` bash
DBPASS=$(grep '^DB_PASSWORD=' /var/www/html/snipe-it/.env | cut -d= -f2-)

mariadb \
  -u snipeit_user \
  -p"$DBPASS" \
  snipeit_db \
  -N \
  -e "SHOW TABLES;" | wc -l
```

If the database must be rebuilt from the backup, use a clean database:

``` bash
mariadb -u root <<SQL
DROP DATABASE IF EXISTS snipeit_db;

CREATE DATABASE snipeit_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

GRANT ALL PRIVILEGES
  ON snipeit_db.*
  TO 'snipeit_user'@'localhost';

FLUSH PRIVILEGES;
SQL
```

Test:

``` bash
mariadb \
  -u snipeit_user \
  -p"$DBPASS" \
  snipeit_db \
  -e "SELECT 2+2 AS result;"
```

Import:

``` bash
mariadb \
  -u snipeit_user \
  -p"$DBPASS" \
  snipeit_db \
  < "$BACKUP_DIR/database/snipeit.sql"
```

Verify:

``` bash
mariadb \
  -u snipeit_user \
  -p"$DBPASS" \
  snipeit_db \
  -N \
  -e "SHOW TABLES;" | wc -l
```

Then:

``` bash
unset DBPASS
```

------------------------------------------------------------------------

# 45. Final automated verification

Run:

``` bash
echo "========== SNIPE-IT RECOVERY CHECK =========="

echo
echo "=== OS ==="
grep PRETTY_NAME /etc/os-release

echo
echo "=== PHP ==="
php -v | head -1

echo
echo "=== MariaDB ==="
mariadb -u root -e "SELECT VERSION();"

echo
echo "=== Git ==="
cd /var/www/html/snipe-it
git log -1 --oneline
git describe --tags --always

echo
echo "=== Snipe-IT version ==="
grep -E \
"app_version|full_app_version|build_version|hash_version" \
config/version.php

echo
echo "=== APP KEY EXISTS ==="
grep '^APP_KEY=' .env | sed 's/=.*/=********/'

echo
echo "=== DB CONNECTIVITY ==="
DBPASS=$(grep '^DB_PASSWORD=' .env | cut -d= -f2-)

mariadb \
  -u snipeit_user \
  -p"$DBPASS" \
  snipeit_db \
  -e "SELECT 2+2 AS result;"

echo
echo "=== TABLE COUNT ==="
mariadb \
  -u snipeit_user \
  -p"$DBPASS" \
  snipeit_db \
  -N \
  -e "SHOW TABLES;" | wc -l

echo
echo "=== DATA COUNTS ==="
mariadb \
  -u snipeit_user \
  -p"$DBPASS" \
  snipeit_db \
  -e "
SELECT COUNT(*) AS users FROM users;
SELECT COUNT(*) AS assets FROM assets;
SELECT COUNT(*) AS models FROM models;
SELECT COUNT(*) AS companies FROM companies;
SELECT COUNT(*) AS locations FROM locations;
"

unset DBPASS

echo
echo "=== SERVICES ==="
systemctl is-active mariadb
systemctl is-active php8.3-fpm
systemctl is-active nginx

echo
echo "=== NGINX ==="
nginx -t

echo
echo "=== PUBLIC UPLOADS ==="
find /var/www/html/snipe-it/public/uploads \
  -type f | wc -l

echo
echo "=== PRIVATE UPLOADS ==="
find /var/www/html/snipe-it/storage/private_uploads \
  -type f | wc -l

echo
echo "========== END CHECK =========="
```

------------------------------------------------------------------------

# 46. Expected successful recovery

``` text
Snipe-IT:
v8.7.2

Build:
24589

Commit:
gf0bd1f8d76

PHP:
8.3.x

Database:
snipeit_db

Database user:
snipeit_user

Database tables:
59 for this specific backup

APP_KEY:
original key preserved

Public uploads:
restored

Private uploads:
restored

OAuth keys:
restored

MariaDB:
active

PHP-FPM:
active

Nginx:
active

Web application:
accessible at /

/setup:
NOT used to create the database
```

------------------------------------------------------------------------

# 47. After the first successful login

Only after the restored system is confirmed:

1.  Configure DNS.
2.  Configure HTTPS.
3.  Configure Snipe-IT scheduler/cron for the installed release.
4.  Configure external/off-server backups.
5.  Create a new tested recovery backup.
6.  Record the new backup checksum.
7.  Perform another clean-VM restore test.

------------------------------------------------------------------------

# 48. Golden recovery procedure

For a future disaster, the high-level sequence is:

``` text
NEW VM
  ↓
Verify backup SHA256
  ↓
Test ZIP
  ↓
Extract backup
  ↓
Verify SHA256SUMS
  ↓
Install Debian packages
  ↓
Install PHP 8.3
  ↓
Install MariaDB
  ↓
Install Nginx
  ↓
Install Composer
  ↓
Clone Snipe-IT
  ↓
Checkout exact original commit
  ↓
composer install
  ↓
Restore original .env
  ↓
Preserve original APP_KEY
  ↓
Create empty database/user
  ↓
Test database credentials
  ↓
Import snipeit.sql
  ↓
Verify tables/data
  ↓
Restore public uploads
  ↓
Restore private uploads
  ↓
Restore OAuth keys
  ↓
Fix permissions
  ↓
Configure Nginx
  ↓
Clear/cache Laravel configuration
  ↓
Restart services
  ↓
Test HTTP
  ↓
Login
  ↓
Verify users/assets/history/uploads
  ↓
HTTPS + scheduler
  ↓
New tested backup
```

------------------------------------------------------------------------

# 49. What must NEVER be changed during initial recovery

``` text
Original APP_KEY
Original database contents
Original users
Original assets
Original asset history
Original migration history
Original OAuth keys
Original upload files
Exact application source version
```

Do not use:

``` bash
php artisan key:generate
php artisan migrate:fresh
php artisan migrate:refresh
php artisan migrate
composer update
```

until the recovered installation is fully understood and a controlled
upgrade/migration is intentionally planned.

# 50. Recovery is complete only when

A successful login alone is not enough.

Confirm all of these:

``` text
[ ] ZIP checksum passed
[ ] ZIP integrity passed
[ ] Extracted SHA256SUMS passed
[ ] Exact Snipe-IT version verified
[ ] Exact Git commit verified
[ ] Composer dependencies installed
[ ] Original APP_KEY preserved
[ ] Database connection tested
[ ] SQL imported
[ ] Table count verified
[ ] Users verified
[ ] Assets verified
[ ] Asset history verified
[ ] Models verified
[ ] Companies verified
[ ] Locations verified
[ ] Public uploads verified
[ ] Private uploads verified
[ ] OAuth keys restored
[ ] Nginx working
[ ] PHP-FPM working
[ ] MariaDB working
[ ] Web login working
[ ] HTTPS configured
[ ] New backup created
[ ] New backup copied off-server
[ ] New backup restore-tested
```

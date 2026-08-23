# Snipe-IT Installation Guide — Ubuntu + nginx + MariaDB

**Tested against:** Ubuntu with PHP 8.3, MariaDB, nginx
**Target audience:** Homelab / small-team self-hosted deployment

---

## 0. Before You Start

Gather this information first — it prevents the most common setup mistake (wrong `APP_URL`, covered in Step 7):

```bash
lsb_release -a          # Confirm your Ubuntu codename (jammy, noble, etc.)
curl -4 ifconfig.me      # Your PUBLIC IP — use this in APP_URL if accessing from outside
ip a                      # Your PRIVATE IP — do NOT use this in APP_URL unless accessing locally only
```

Write both IPs down. If you're on a cloud VM (EC2, etc.), the public IP may be **dynamic** and change on reboot unless you've reserved a static/elastic IP — plan accordingly.

---

## 1. Update System & Check Existing PHP Version

**Always check what's already available before adding a third-party repo.** Recent Ubuntu releases often ship PHP 8.2+ by default, making extra repos unnecessary.

```bash
sudo apt update && sudo apt upgrade -y
apt-cache madison php8.3-cli
```

- **If this shows a candidate** (e.g. `php8.3-cli | 8.3.x | ...`) → skip to Step 2, no extra repo needed.
- **If nothing shows / version is too old** → add the sury.org PHP repository:

```bash
sudo apt install -y ca-certificates apt-transport-https curl gnupg
curl -sSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb
sudo dpkg -i /tmp/debsuryorg-archive-keyring.deb
sudo sh -c 'echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list'
sudo apt update
```

> ⚠️ **Do not use the `ondrej/php` PPA** on very new Ubuntu releases — it may not have builds for your release yet and will 404. sury.org is the actively maintained source.
>
> ⚠️ **If both Ubuntu's own repo and sury.org offer PHP**, apt may refuse to resolve virtual packages like `php-cli`, `php-fileinfo`, `php-ctype` because two providers compete. **The fix is to always use fully-versioned package names** (`php8.3-cli`, not `php-cli`) — see Step 2.

---

## 2. Install PHP 8.3 and Required Extensions

Use **fully-versioned package names** throughout — this avoids ambiguity errors entirely, even with multiple PHP repos enabled:

```bash
sudo apt install -y php8.3 php8.3-cli php8.3-fpm php8.3-common php8.3-mysql \
  php8.3-gd php8.3-bcmath php8.3-mbstring php8.3-xml php8.3-curl php8.3-zip \
  php8.3-tokenizer php8.3-intl php8.3-ldap php8.3-soap
```

Note: `php-fileinfo`, `php-ctype`, and `php-xsl` don't need separate lines — `php8.3-common` and `php8.3-xml` already bundle them.

Verify:

```bash
php -v
```

Expected output: `PHP 8.3.x`

---

## 3. Install MariaDB, nginx, Git, and Utilities

```bash
sudo apt install -y mariadb-server nginx git unzip curl graphviz
```

**Enable and start services — do this with explicit names, not wildcards.** (`systemctl enable --now php*-fpm` fails; systemd doesn't expand shell globs.)

```bash
sudo systemctl enable --now mariadb
sudo systemctl enable --now nginx
sudo systemctl enable --now php8.3-fpm
```

Verify all three are active:

```bash
systemctl status mariadb nginx php8.3-fpm --no-pager
```

Also confirm the actual PHP-FPM socket filename (you'll need this exact path in Step 8):

```bash
ls /run/php/
```

---

## 4. Secure MariaDB & Create the Database

```bash
sudo mariadb-secure-installation
```

Prompts to answer:
| Prompt | Answer |
|---|---|
| Enter current password for root | Press Enter (fresh install = no password yet) |
| Switch to unix_socket authentication? | `n` |
| Set root password? | `Y` → set a strong password |
| Remove anonymous users? | `Y` |
| Disallow root login remotely? | `Y` |
| Remove test database? | `Y` |
| Reload privilege tables now? | `Y` |

Create the Snipe-IT database and user:

```bash
sudo mysql -u root -p
```

```sql
CREATE DATABASE snipeit_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'snipeit_user'@'localhost' IDENTIFIED BY 'YourSecurePassword';
GRANT ALL PRIVILEGES ON snipeit_db.* TO 'snipeit_user'@'localhost';
FLUSH PRIVILEGES;
EXIT;
```

> Replace `YourSecurePassword` with a real password and remember it — it goes into `.env` in Step 6.

---

## 5. Install Composer

```bash
curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer
composer --version
```

---

## 6. Clone Snipe-IT and Install Dependencies

**Set up www-data's cache/config directories BEFORE running Composer** — this prevents both the "cache directory not writable" error and the GitHub-token prompt caused by running out of anonymous API rate limit.

```bash
sudo mkdir -p /var/www/html /var/www/.cache /var/www/.config
sudo chown -R www-data:www-data /var/www/.cache /var/www/.config

cd /var/www/html
sudo git clone --depth 1 https://github.com/snipe/snipe-it.git snipe-it
sudo chown -R www-data:www-data /var/www/html/snipe-it
cd /var/www/html/snipe-it
```

```bash
sudo -u www-data composer install --no-dev --prefer-dist
```

> ⚠️ **Do not use `--prefer-source`.** It forces Composer to `git clone` all 166+ dependency packages individually, which quickly exhausts GitHub's anonymous rate limit and demands a personal access token mid-install. `--prefer-dist` (shown above) downloads zip archives instead and avoids this entirely.

---

## 7. Configure `.env`

```bash
sudo cp .env.example .env
sudo nano .env
```

Set these values:

```ini
APP_URL=http://YOUR_PUBLIC_IP
APP_TIMEZONE='Asia/Dhaka'

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_DATABASE=snipeit_db
DB_USERNAME=snipeit_user
DB_PASSWORD=YourSecurePassword
```

> ⚠️ **This is the #1 cause of a broken-looking install.** `APP_URL` must match the address you'll actually type into your browser.
> - Accessing from outside the server/VPC (e.g. from your laptop over the internet) → use the **public IP** (from Step 0), not the private one.
> - Accessing only from inside the same local network → private IP is fine.
> - Getting this wrong causes Snipe-IT's setup redirect to point somewhere your browser can't reach, which looks like the install "isn't working" when it actually is.
>
> Timezone reference: Dhaka = `Asia/Dhaka` (UTC+6, no DST). Adjust if hosting elsewhere.

---

## 8. Set File Permissions & Generate App Key

```bash
sudo chown -R www-data:www-data /var/www/html/snipe-it
sudo find /var/www/html/snipe-it -type f -exec chmod 644 {} \;
sudo find /var/www/html/snipe-it -type d -exec chmod 755 {} \;
sudo chmod -R 775 /var/www/html/snipe-it/storage
sudo chmod -R 775 /var/www/html/snipe-it/public/uploads

sudo -u www-data php artisan key:generate
```

---

## 9. Configure nginx

Confirm your PHP-FPM socket name matches what you saw in Step 3 (`ls /run/php/`), then create the site config:

```bash
sudo nano /etc/nginx/sites-available/snipeit
```

```nginx
server {
        listen 80;
        server_name YOUR_PUBLIC_IP;
        root /var/www/html/snipe-it/public;
        index index.php;

        location / {
                try_files $uri $uri/ /index.php?$query_string;
        }

        location ~ \.php$ {
                include snippets/fastcgi-php.conf;
                fastcgi_pass unix:/run/php/php8.3-fpm.sock;
                fastcgi_split_path_info ^(.+\.php)(/.+)$;
                fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
                include fastcgi_params;
        }
}
```

Enable the site and reload:

```bash
sudo ln -s /etc/nginx/sites-available/snipeit /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

---

## 10. Open the Firewall

```bash
sudo ufw allow 'Nginx Full'
sudo ufw allow OpenSSH
```

> If `ufw` isn't enabled yet, running `sudo ufw enable` will start enforcing rules — make sure `OpenSSH` is allowed **before** enabling it, or you can lock yourself out over SSH.

---

## 11. Complete the Web-Based Setup

Visit in a browser:

```
http://YOUR_PUBLIC_IP/setup
```

Follow the guided installer — it verifies requirements, runs database migrations, and creates your admin account.

If it hangs or redirects somewhere unreachable, re-check `APP_URL` in `.env`, then clear the cache:

```bash
sudo -u www-data php artisan config:clear
sudo -u www-data php artisan cache:clear
```

---

## Troubleshooting Reference

| Symptom | Cause | Fix |
|---|---|---|
| `Package 'php-xxx' has no installation candidate` / "virtual package" error | Ambiguous package name across multiple PHP repos | Use versioned names: `php8.3-xxx` |
| `Invalid unit name "php*-fpm"` | systemctl doesn't expand shell globs | Use exact name: `sudo systemctl enable --now php8.3-fpm` |
| `Cannot create cache directory /var/www/.cache/...` | www-data has no writable home | `sudo mkdir -p /var/www/.cache && sudo chown -R www-data:www-data /var/www/.cache` |
| Composer prompts for a GitHub token | `--prefer-source` triggered per-package git clones, hit rate limit | Reinstall with `--prefer-dist` instead |
| `fatal: detected dubious ownership in repository` | Repo owned by `root`, command run as different user | `sudo chown -R www-data:www-data /var/www/html/snipe-it` |
| Page redirects to an IP your browser can't reach | `APP_URL` in `.env` set to private IP while accessing from outside | Set `APP_URL` to your public IP, then `php artisan config:clear` |
| nginx serves default welcome page, not Snipe-IT | Site not enabled / wrong `root` path | Check `sudo nginx -t`, confirm symlink in `sites-enabled/` |
| 502 Bad Gateway | `fastcgi_pass` socket path doesn't match installed PHP-FPM version | Run `ls /run/php/` and match the exact filename in the nginx config |

---

## Resource Requirements

| Scale | CPU | RAM | Storage |
|---|---|---|---|
| Homelab / <50 assets | 1 vCPU | 1–2 GB | 10–15 GB |
| Small team / few hundred assets | 2 vCPU | 2–4 GB | 20–30 GB |

Storage growth comes mainly from `storage/app` and `public/uploads` (asset photos, license files) — check with:

```bash
du -sh /var/www/html/snipe-it/storage/app
df -h /var/www/html
```

---

## Backup & Disaster Recovery

**What to back up:** the database, plus `storage/` and `.env` (these hold your encryption key and uploaded files). The core app code can always be re-cloned from GitHub.

### Database backup

```bash
sudo mysqldump -u root -p snipeit_db > snipeit_db_$(date +%F).sql
```

### Files backup

```bash
sudo tar -czf snipeit_storage_$(date +%F).tar.gz -C /var/www/html/snipe-it storage .env
```

### Automate daily backups with cron

```bash
sudo crontab -e
```

```
0 2 * * * mysqldump -u root -pYourSecurePassword snipeit_db > /var/backups/snipeit_db_$(date +\%F).sql
```

> Storing the password in cleartext in crontab isn't ideal — using a `.my.cnf` credentials file is safer for production use.

### Full recovery (server lost entirely)

1. Provision a new Ubuntu VM and repeat Steps 1–5 of this guide.
2. Restore the database: `sudo mysql -u root -p snipeit_db < snipeit_db_YYYY-MM-DD.sql`
3. Extract your `storage/` and `.env` backup into the freshly cloned Snipe-IT folder.
4. Re-run Step 8 (permissions) and Step 9 (nginx).
5. Run `php artisan config:clear` and verify the site loads.

### Extra safety net

If hosting on a cloud VM, take a full VM/disk snapshot right after your first successful setup — this gives you a known-good rollback point that's faster to restore than rebuilding from scratch.
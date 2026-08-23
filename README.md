# Snipe-IT Backup System — Local + Remote (SSH) + S3, GPG-Encrypted

A production-grade backup system for Snipe-IT with three independent, parallel backup
destinations, each fully configurable via its own `.env` file — no hardcoded values
anywhere in the scripts themselves.

## What's Included

```
snipeit-backup-system/
├── common.sh                      # Shared functions (dump, encrypt, decrypt, cleanup)
├── local.env                      # Config for local backups
├── remote.env                     # Config for remote (SSH) backups
├── s3.env                         # Config for S3 backups
├── backup-local.sh                # Backs up to a local directory
├── backup-remote.sh               # Backs up to a remote server via SSH/rsync
├── backup-s3.sh                   # Backs up to an S3 bucket
├── restore.sh                     # Generic restore script (works with any source)
├── snipeit-backup-local.service   # systemd unit for local backup
├── snipeit-backup-remote.service  # systemd unit for remote backup
├── snipeit-backup-s3.service      # systemd unit for S3 backup
└── README.md                      # This file
```

## Design Decisions (and why)

- **systemd services instead of cron.** You wanted intervals configurable down to
  seconds (`10s`, `10min`, `1hr`). Cron's minimum granularity is 1 minute, so each
  script instead runs as a **long-lived loop**, sleeping for `BACKUP_INTERVAL_SECONDS`
  (read from its `.env`) between cycles. systemd keeps it alive and restarts it
  automatically if it ever crashes.
- **Everything encrypted before it leaves the disk.** Every backup is GPG
  (AES256, passphrase-based) encrypted immediately after creation, and the
  plaintext `.sql`/`.tar.gz` files are deleted within the same script execution —
  they never sit on disk unencrypted for more than a few seconds, and never
  travel over the network unencrypted at all.
- **Three fully independent scripts.** Each destination (local / remote / S3) has
  its own script, its own `.env`, and its own systemd service — you can enable,
  disable, or reconfigure any one of them without touching the others.
- **Shared logic lives in `common.sh`.** Dump/archive/encrypt/decrypt/cleanup
  functions are written once and sourced by all three scripts, so fixing a bug or
  changing encryption settings only needs to happen in one place.

---

## Part 1 — Prerequisites

- Snipe-IT already installed and working (`/var/www/html/snipe-it` in this guide —
  adjust paths in the `.env` files if yours differs)
- `gpg` installed (`sudo apt install -y gnupg` if missing)
- For **remote backup**: a second server reachable over SSH, with a dedicated
  SSH key set up (see Part 3)
- For **S3 backup**: AWS CLI installed (`sudo apt install -y awscli` or the
  official installer) and either an IAM role attached to the EC2 instance, or
  credentials configured via `aws configure` as root

---

## Part 2 — Install the Backup System

Copy this entire folder onto the Snipe-IT server:

```bash
sudo mkdir -p /opt/snipeit-backup-system
sudo cp -r ./snipeit-backup-system/* /opt/snipeit-backup-system/
cd /opt/snipeit-backup-system

sudo chmod +x backup-local.sh backup-remote.sh backup-s3.sh restore.sh common.sh
sudo chown -R root:root /opt/snipeit-backup-system
```

---

## Part 3 — Create the Encryption Passphrase (used by all three scripts)

```bash
sudo mkdir -p /root/.secrets
sudo nano /root/.secrets/backup_passphrase.txt
sudo sh -c 'openssl rand -base64 768 | tr -d "\n" | cut -c1-1000 > /root/.secrets/backup_passphrase.txt'
sudo cat /root/.secrets/backup_passphrase.txt
```

Paste a strong, random passphrase — single line, no trailing spaces. Lock it down:

```bash
sudo chmod 600 /root/.secrets/backup_passphrase.txt
sudo chown root:root /root/.secrets/backup_passphrase.txt
```

> ⚠️ **Save a copy of this passphrase somewhere outside this server** (password
> manager, secure notes, etc). If this server is lost and the passphrase only
> existed here, every encrypted backup — local, remote, and S3 — becomes
> permanently unreadable. This single file is the most critical part of the
> entire system.

---

## Part 4 — Configure Each `.env` File

### `local.env` — usually needs no changes, just review paths and interval:

```ini
STORAGE_DIR=/var/www/html/snipe-it
LOCAL_BACKUP_DIR=/var/backups/snipeit/local
RETENTION_MINUTES=1440          # 1 day
BACKUP_INTERVAL_SECONDS=3600    # every hour
```

### `remote.env` — set up SSH access first, then fill in:

```bash
sudo -u root ssh-keygen -t ed25519 -f /root/.ssh/snipeit_backup_key -N ""
```

Add the new public key to the remote server **without removing any existing key**
(e.g. your normal `.pem` login key) — log in with your existing key and append:

```bash
# On the SOURCE server:
cat /root/.ssh/snipeit_backup_key.pub
```

```bash
# On the REMOTE server, logged in via your existing key:
echo "PASTE_THE_PUBLIC_KEY_HERE" >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys
mkdir -p ~/snipeit-backups
```

Verify it works without a password:

```bash
sudo ssh -i /root/.ssh/snipeit_backup_key REMOTE_USER@REMOTE_HOST "echo connected"
```

Then edit `remote.env`:

```ini
REMOTE_USER=ubuntu
REMOTE_HOST=your.remote.server.ip
REMOTE_DIR=~/snipeit-backups
SSH_KEY=/root/.ssh/snipeit_backup_key
RETENTION_MINUTES=10080         # 7 days
BACKUP_INTERVAL_SECONDS=600     # every 10 minutes
```

### `s3.env` — create a bucket and set credentials:

If running on EC2, attaching an IAM role with `s3:PutObject`, `s3:ListBucket`,
`s3:DeleteObject` permissions on your bucket is cleaner than static keys. Otherwise:

```bash
sudo aws configure
# Enter Access Key ID, Secret Access Key, region
```

Edit `s3.env`:

```ini
S3_BUCKET=your-bucket-name
S3_PREFIX=snipeit-backups
AWS_REGION=ap-southeast-1
RETENTION_DAYS=30
BACKUP_INTERVAL_SECONDS=3600    # every hour
```

Test AWS CLI access manually before trusting the script:

```bash
aws s3 ls s3://your-bucket-name/
```

---

## Part 5 — Run as systemd Services

Copy the unit files into place:

```bash
sudo cp /opt/snipeit-backup-system/snipeit-backup-local.service /etc/systemd/system/
sudo cp /opt/snipeit-backup-system/snipeit-backup-remote.service /etc/systemd/system/
sudo cp /opt/snipeit-backup-system/snipeit-backup-s3.service /etc/systemd/system/

sudo systemctl daemon-reload
```

Enable and start whichever ones you want running (you don't have to enable all three
— e.g. skip S3 if you're not using it yet):

```bash
sudo systemctl enable --now snipeit-backup-local.service
sudo systemctl enable --now snipeit-backup-remote.service
sudo systemctl enable --now snipeit-backup-s3.service
```

Check status:

```bash
sudo systemctl status snipeit-backup-local.service --no-pager
sudo systemctl status snipeit-backup-remote.service --no-pager
sudo systemctl status snipeit-backup-s3.service --no-pager
```

Watch logs live:

```bash
tail -f /var/log/snipeit_backup_local.log
tail -f /var/log/snipeit_backup_remote.log
tail -f /var/log/snipeit_backup_s3.log
```

Or via journalctl:

```bash
sudo journalctl -u snipeit-backup-local.service -f
```

### Changing the interval later

Edit the relevant `.env` file (e.g. change `BACKUP_INTERVAL_SECONDS=600` to `=60`),
then restart just that service — no need to touch the others:

```bash
sudo nano /opt/snipeit-backup-system/remote.env
sudo systemctl restart snipeit-backup-remote.service
```

### Stopping a service

```bash
sudo systemctl stop snipeit-backup-s3.service
sudo systemctl disable snipeit-backup-s3.service   # if you want it to stay off after reboot too
```

---

## Part 6 — Test Each Script Manually Before Trusting the Service

Run one cycle immediately, without waiting for the loop:

```bash
sudo /opt/snipeit-backup-system/backup-local.sh --once
sudo /opt/snipeit-backup-system/backup-remote.sh --once
sudo /opt/snipeit-backup-system/backup-s3.sh --once
```

Then verify:

```bash
# Local
ls -lh /var/backups/snipeit/local/

# Remote
sudo ssh -i /root/.ssh/snipeit_backup_key REMOTE_USER@REMOTE_HOST "ls -lh ~/snipeit-backups"

# S3
aws s3 ls s3://your-bucket-name/snipeit-backups/
```

---

## Part 7 — Production Note on S3 Retention

`cleanup_s3()` in `common.sh` works fine for moderate backup volumes, but for
larger-scale or long-running production use, an **S3 Lifecycle Rule** is the more
robust and cost-effective way to expire old objects (no script logic needed, and it
survives even if this server is lost). To set one up:

**AWS Console → S3 → your bucket → Management → Lifecycle rules → Create rule**
- Scope: prefix `snipeit-backups/`
- Action: Expire current versions of objects after `N` days

If you set up a Lifecycle Rule, you can simplify `s3.env` by setting
`RETENTION_DAYS` very high (effectively disabling the script's own cleanup) and
let S3 handle expiry natively.

---

## Part 8 — Restore Procedure

The same `restore.sh` script works regardless of which backup source you're
restoring from — you just need the two `.gpg` files present on the restore target.

### Step 1: Get the encrypted backup files onto the restore target

**From local backup** (if restoring on the same server, files are already there):

```bash
ls /var/backups/snipeit/local/
```

**From remote backup:**

```bash
scp -i /root/.ssh/snipeit_backup_key \
  REMOTE_USER@REMOTE_HOST:~/snipeit-backups/snipeit_db_TIMESTAMP.sql.gpg \
  REMOTE_USER@REMOTE_HOST:~/snipeit-backups/snipeit_storage_TIMESTAMP.tar.gz.gpg \
  /tmp/
```

**From S3:**

```bash
aws s3 cp s3://your-bucket-name/snipeit-backups/snipeit_db_TIMESTAMP.sql.gpg /tmp/
aws s3 cp s3://your-bucket-name/snipeit-backups/snipeit_storage_TIMESTAMP.tar.gz.gpg /tmp/
```

### Step 2: Prepare the target server

If restoring onto a **fresh server**, complete a normal Snipe-IT install first
(PHP, MariaDB, nginx, Composer, git clone, and database creation) — but **skip**
the web-based setup wizard, since you're restoring existing data instead of
starting fresh.

Also copy the passphrase file onto this server if it isn't already there
(retrieve from your password manager):

```bash
sudo mkdir -p /root/.secrets
sudo nano /root/.secrets/backup_passphrase.txt   # paste the same passphrase
sudo chmod 600 /root/.secrets/backup_passphrase.txt
```

Also copy `restore.sh` onto this server if it's a different machine than the source:

```bash
sudo mkdir -p /opt/snipeit-backup-system
sudo cp restore.sh /opt/snipeit-backup-system/
sudo chmod +x /opt/snipeit-backup-system/restore.sh
```

### Step 3: Run the restore

```bash
cd /opt/snipeit-backup-system
sudo ./restore.sh /tmp/snipeit_db_TIMESTAMP.sql.gpg /tmp/snipeit_storage_TIMESTAMP.tar.gz.gpg
```

The script will:
1. Decrypt both files
2. Sanity-check the SQL file actually looks like a real dump before touching anything
3. Ask for confirmation before overwriting the database
4. Restore the database
5. Restore `storage/` and `.env` into the Snipe-IT directory, fix ownership/permissions
6. Clear Laravel's config/cache
7. Delete the temporary decrypted files

### Step 4: Verify

Load the site in a browser and confirm your assets, licenses, and users are present.

---

## Part 9 — Testing on a Separate Test Server (End-to-End Verification)

Since you want to test the full cycle on another server before trusting it in
production, here's the exact test sequence:

1. **On the test server:** install Snipe-IT fresh, up through database creation
   (don't run the setup wizard).
2. **On the production/source server:** confirm a recent successful backup exists
   in whichever destination you're testing (local/remote/S3).
3. **Transfer the two `.gpg` files** to the test server (scp from remote, or
   `aws s3 cp` from S3, or just copy directly if testing the local backup).
4. **Copy `restore.sh` and the passphrase file** onto the test server as described
   in Part 8, Step 2.
5. **Run `restore.sh`** with the two file paths.
6. **Load the test server's Snipe-IT URL** in a browser and confirm:
   - Login works with your original admin credentials
   - Assets, licenses, users, and categories all match what was in production
     at backup time
   - Any uploaded files (asset photos, license documents) open correctly

If all of that checks out, your backup and restore pipeline is fully verified.
Repeat this test periodically (e.g. monthly) — a backup that's never been
restored from is unverified, regardless of how long it's been running successfully.

---

## Quick Reference

| Task | Command |
|---|---|
| Run local backup once | `sudo /opt/snipeit-backup-system/backup-local.sh --once` |
| Run remote backup once | `sudo /opt/snipeit-backup-system/backup-remote.sh --once` |
| Run S3 backup once | `sudo /opt/snipeit-backup-system/backup-s3.sh --once` |
| Check service status | `sudo systemctl status snipeit-backup-<local\|remote\|s3>.service` |
| Watch live logs | `sudo journalctl -u snipeit-backup-<local\|remote\|s3>.service -f` |
| Change backup interval | Edit `.env` → `sudo systemctl restart snipeit-backup-<name>.service` |
| Restore from backup | `sudo /opt/snipeit-backup-system/restore.sh <db.sql.gpg> <storage.tar.gz.gpg>` |
| Manually decrypt a file | `gpg --batch --yes --passphrase-file /root/.secrets/backup_passphrase.txt --decrypt -o OUT IN.gpg` |

#!/bin/bash
set -e

# --- DIAGNOSTIC COMMAND ---
# This will run when the container starts and show us what was actually copied.
echo "--- START DIAGNOSIS OF FINAL IMAGE AT RUNTIME ---"
ls -lR /opt/cloudsaver
echo "--- END DIAGNOSIS OF FINAL IMAGE AT RUNTIME ---"
# The script will likely fail after this, which is okay for now.

# The rest of the script is the same...

# --- 1. Set SSH Password ---
if [ -n "$SSH_PASSWORD" ]; then
    echo "INFO: Root password is being set from the SSH_PASSWORD environment variable."
    PASSWORD=$SSH_PASSWORD
else
    echo "INFO: SSH_PASSWORD environment variable not set. Using default password 'admin123'."
    PASSWORD="admin123"
fi
echo "root:$PASSWORD" | chpasswd
echo "INFO: SSH root password has been set."

# --- 2. Create All Necessary Persistent Directories ---
echo "INFO: Ensuring all persistent directories exist..."
mkdir -p /var/www/html/cloudsaver_data
mkdir -p /var/www/html/mysql_data
mkdir -p /var/www/html/logs
mkdir -p /var/www/html/supervisor/conf.d
mkdir -p /var/www/html/cron

# --- 3. Prepare CloudSaver Environment ---
echo "INFO: Preparing CloudSaver environment..."
DEFAULT_ENV_TEMPLATE="/opt/cloudsaver/config/env"
PERSISTENT_ENV_FILE="/var/www/html/cloudsaver_data/.env"
SYMLINK_PATH="/opt/cloudsaver/.env"

if [ ! -f "$PERSISTENT_ENV_FILE" ]; then
    echo "INFO: No existing .env file found. Copying default template..."
    cp "$DEFAULT_ENV_TEMPLATE" "$PERSISTENT_ENV_FILE"
    echo "INFO: Default .env file created at $PERSISTENT_ENV_FILE."
    echo "IMPORTANT: You should edit this file to set your JWT_SECRET!"
else
    echo "INFO: Existing .env file found. Skipping copy."
fi
ln -sfn "$PERSISTENT_ENV_FILE" "$SYMLINK_PATH"
echo "INFO: CloudSaver is now linked to the persistent .env file."

# --- 4. Initialize MySQL Database ---
if [ -z "$(ls -A /var/www/html/mysql_data)" ]; then
    echo "INFO: MySQL data directory is empty. Initializing database..."
    mysqld --initialize-insecure --user=mysql --datadir=/var/www/html/mysql_data
    echo "INFO: Database initialized."
else
    echo "INFO: MySQL data directory already exists. Skipping initialization."
fi

# --- 5. Set Final Permissions ---
echo "INFO: Setting final permissions for persistent volume..."
chown -R www-data:www-data /var/www/html
chown -R mysql:mysql /var/www/html/mysql_data
echo "INFO: Permissions set."

# --- 6. Start All Services ---
echo "INFO: Starting all services via Supervisor..."
exec "$@"

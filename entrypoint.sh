#!/bin/bash
set -e

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

# --- 2. Create Runtime Directories (THE FIX for sshd and php-fpm) ---
# Services need these directories at runtime, and they may not exist in a clean container.
echo "INFO: Creating runtime directories..."
mkdir -p /var/run/sshd
mkdir -p /var/run/php

# --- 3. Create All Necessary Persistent Directories ---
echo "INFO: Ensuring all persistent directories exist..."
mkdir -p /var/www/html/cloudsaver_data
mkdir -p /var/www/html/mysql_data
mkdir -p /var/www/html/logs
mkdir -p /var/www/html/supervisor/conf.d
mkdir -p /var/www/html/cron

# --- 4. Prepare CloudSaver Environment ---
echo "INFO: Preparing CloudSaver environment..."
PERSISTENT_ENV_FILE="/var/www/html/cloudsaver_data/.env"
SYMLINK_PATH="/opt/cloudsaver/.env"

if [ ! -f "$PERSISTENT_ENV_FILE" ]; then
    echo "INFO: No existing .env file found. Creating a default one..."
    echo "JWT_SECRET=your_jwt_secret_here" > "$PERSISTENT_ENV_FILE"
    echo "IMPORTANT: The default .env file has been created at $PERSISTENT_ENV_FILE. Please edit it to set a real JWT_SECRET!"
else
    echo "INFO: Existing .env file found. Skipping creation."
fi
ln -sfn "$PERSISTENT_ENV_FILE" "$SYMLINK_PATH"
echo "INFO: CloudSaver is now linked to the persistent .env file."

# --- 5. Initialize MySQL Database ---
if [ -z "$(ls -A /var/www/html/mysql_data)" ]; then
    echo "INFO: MySQL data directory is empty. Initializing database..."
    mysqld --initialize-insecure --user=mysql --datadir=/var/www/html/mysql_data
    echo "INFO: Database initialized."
else
    echo "INFO: MySQL data directory already exists. Skipping initialization."
fi

# --- 6. Set Final Permissions ---
echo "INFO: Setting final permissions for persistent volume..."
chown -R www-data:www-data /var/www/html
chown -R mysql:mysql /var/www/html/mysql_data
echo "INFO: Permissions set."

# --- 7. Start All Services ---
echo "INFO: Starting all services via Supervisor..."
exec "$@"

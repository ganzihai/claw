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

# --- 2. Create Runtime Directories & Log Files (ROBUSTNESS FIX) ---
echo "INFO: Creating runtime directories and ensuring log files exist..."
mkdir -p /var/run/sshd
# Pre-create log files to prevent startup race conditions
mkdir -p /var/www/html/logs
touch /var/www/html/logs/nginx_access.log /var/www/html/logs/nginx_error.log
touch /var/www/html/logs/cloudsaver.log /var/www/html/logs/cloudsaver_error.log
# Ensure all other persistent directories exist
mkdir -p /var/www/html/supervisor/conf.d \
         /var/www/html/mysql_data \
         /var/www/html/cloudsaver_data \
         /var/www/html/cron

# --- 3. Prepare CloudSaver Environment ---
echo "INFO: Preparing CloudSaver environment..."
PERSISTENT_DATA_DIR="/var/www/html/cloudsaver_data"
PERSISTENT_CONFIG_DEST="$PERSISTENT_DATA_DIR/config.yml"
DEFAULT_CONFIG_SRC="/opt/cloudsaver/config/config.yml"
ln -sfn "$PERSISTENT_DATA_DIR" /opt/cloudsaver/data
if [ ! -f "$PERSISTENT_CONFIG_DEST" ]; then
    if [ -f "$DEFAULT_CONFIG_SRC" ]; then
        cp "$DEFAULT_CONFIG_SRC" "$PERSISTENT_CONFIG_DEST"
        echo "INFO: Default CloudSaver config copied."
    else
        echo "WARNING: Default CloudSaver config file was not found at $DEFAULT_CONFIG_SRC."
    fi
else
    echo "INFO: Existing CloudSaver config found. Skipping copy."
fi

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

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


# --- 2. Prepare CloudSaver Environment (Correct .env file logic) ---
echo "INFO: Preparing CloudSaver environment..."

# Define paths
DEFAULT_ENV_TEMPLATE="/opt/cloudsaver/config/env"
PERSISTENT_DATA_DIR="/var/www/html/cloudsaver_data"
PERSISTENT_ENV_FILE="$PERSISTENT_DATA_DIR/.env"
SYMLINK_PATH="/opt/cloudsaver/.env"

# Ensure the persistent data directory exists
mkdir -p "$PERSISTENT_DATA_DIR"

# Only copy the default .env template if the user has not provided their own.
# This check makes the setup robust and preserves user changes on restart.
if [ ! -f "$PERSISTENT_ENV_FILE" ]; then
    echo "INFO: No existing .env file found in $PERSISTENT_DATA_DIR. Copying default template..."
    if [ -f "$DEFAULT_ENV_TEMPLATE" ]; then
        cp "$DEFAULT_ENV_TEMPLATE" "$PERSISTENT_ENV_FILE"
        echo "INFO: Default .env file created at $PERSISTENT_ENV_FILE."
        echo "IMPORTANT: You should edit this file to set your JWT_SECRET!"
    else
        # This is a fallback warning, but our Dockerfile should always copy the file.
        echo "WARNING: Default env template was not found at $DEFAULT_ENV_TEMPLATE. CloudSaver may fail."
    fi
else
    echo "INFO: Existing .env file found at $PERSISTENT_ENV_FILE. Skipping copy."
fi

# Create a symlink from the app's working directory to the persistent .env file.
# The Node.js app will find the .env file in its CWD via this link.
ln -sfn "$PERSISTENT_ENV_FILE" "$SYMLINK_PATH"
echo "INFO: CloudSaver is now linked to the persistent .env file."


# --- 3. Set permissions for the mounted volume ---
chown -R www-data:www-data /var/www/html
chown -R mysql:mysql /var/www/html/mysql_data


# --- 4. Initialize MySQL Database if not already initialized ---
if [ -z "$(ls -A /var/www/html/mysql_data)" ]; then
    echo "INFO: MySQL data directory is empty. Initializing database..."
    mysqld --initialize-insecure --user=mysql --datadir=/var/www/html/mysql_data
    echo "INFO: Database initialized."
else
    echo "INFO: MySQL data directory already exists. Skipping initialization."
fi

echo "INFO: Starting all services via Supervisor..."

# Execute the command passed to the script (CMD from Dockerfile)
exec "$@"

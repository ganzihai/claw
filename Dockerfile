# =========================================================================
# STAGE 1: Extract CloudSaver binary from its official image
# =========================================================================
FROM jiangrui1994/cloudsaver:latest AS cloudsaver_stage

# =========================================================================
# STAGE 2: Main build stage for the fat image
# =========================================================================
FROM ubuntu:22.04

# --- Environment and Arguments ---
ARG DEBIAN_FRONTEND=noninteractive
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8

# --- 1. Install Base Packages & Dependencies ---
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    software-properties-common \
    git \
    openssh-server \
    sudo \
    curl \
    wget \
    cron \
    nano \
    tar \
    gzip \
    unzip \
    sshpass \
    python3 \
    python3-pip \
    nginx \
    supervisor \
    mysql-server && \
    rm -rf /var/lib/apt/lists/*

# --- 2. Install Go Language Environment ---
RUN wget https://go.dev/dl/go1.24.4.linux-amd64.tar.gz -O /tmp/go.tar.gz && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && \
    rm /tmp/go.tar.gz
ENV PATH="/usr/local/go/bin:${PATH}"

# --- 3. Install Node.js Environment (LTS) ---
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# --- 4. Install PHP 7.4 and Extensions for Maccms ---
# Maccms v10 requires PHP 7.1-7.4. We will install 7.4.
# Adding PPA for older PHP versions on Ubuntu 22.04
RUN add-apt-repository ppa:ondrej/php -y && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    php7.4-fpm \
    php7.4-mysql \
    php7.4-gd \
    php7.4-curl \
    php7.4-mbstring \
    php7.4-xml \
    php7.4-zip \
    php7.4-bcmath \
    php7.4-soap \
    php7.4-intl \
    php7.4-readline && \
    rm -rf /var/lib/apt/lists/*

# --- 5. Integrate CloudSaver from the first stage (CORRECTED & MORE SPECIFIC) ---
# Create a dedicated directory for the CloudSaver Node.js app
RUN mkdir -p /opt/cloudsaver
# Copy the compiled application and its dependencies
COPY --from=cloudsaver_stage /app/dist-final /opt/cloudsaver/dist-final
COPY --from=cloudsaver_stage /app/node_modules /opt/cloudsaver/node_modules
COPY --from=cloudsaver_stage /app/package.json /opt/cloudsaver/package.json
# EXPLICITLY create the config directory and copy the 'env' template file into it
RUN mkdir -p /opt/cloudsaver/config
COPY --from=cloudsaver_stage /app/config/env /opt/cloudsaver/config/env

# --- 6. Configure Services ---

# Configure SSH
RUN mkdir -p /var/run/sshd && \
    # Allow root login via password, useful for debugging in container environments.
    # For production, consider key-based auth.
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# Configure Supervisor
# We will copy a master config file, which includes configs from the mounted volume.
COPY supervisord.conf /etc/supervisor/supervisord.conf
RUN mkdir -p /var/log/supervisor

# Configure Nginx
# Copy a custom site configuration for Maccms.
COPY nginx-maccms.conf /etc/nginx/sites-available/maccms
RUN ln -s /etc/nginx/sites-available/maccms /etc/nginx/sites-enabled/maccms && \
    rm /etc/nginx/sites-enabled/default

# Configure PHP-FPM
# Ensure PHP-FPM doesn't daemonize, so Supervisor can manage it.
RUN sed -i 's/;daemonize = yes/daemonize = no/' /etc/php/7.4/fpm/php-fpm.conf

# Configure MySQL
# IMPORTANT: Point MySQL data directory to the persistent volume.
RUN sed -i 's|datadir\s*=\s*/var/lib/mysql|datadir = /var/www/html/mysql_data|' /etc/mysql/mysql.conf.d/mysqld.cnf && \
    sed -i 's|#bind-address\s*=\s*127.0.0.1|bind-address = 127.0.0.1|' /etc/mysql/mysql.conf.d/mysqld.cnf

# --- 7. Setup Scripts, Permissions and Entrypoint ---

# Copy the entrypoint script that will run on container start
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Create necessary directories on the persistent volume
# The entrypoint script will handle ownership
RUN mkdir -p /var/www/html/supervisor/conf.d \
             /var/www/html/mysql_data \
             /var/www/html/cloudsaver_data \
             /var/www/html/logs \
             /var/www/html/cron

# --- 8. Final Steps ---

# Expose port 80 as per project rules
EXPOSE 80

# Set the entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# The CMD will be executed by the entrypoint script
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]

# =========================================================================
# STAGE 1: Reference the CloudSaver image
# =========================================================================
FROM jiangrui1994/cloudsaver:latest AS cloudsaver_stage

# =========================================================================
# STAGE 2: Main build stage for the fat image (FINAL SHOWSTOPPER FIX)
# =========================================================================
FROM ubuntu:22.04

# --- Environment and Arguments ---
ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8

# --- 1. Install Base Packages & Dependencies (MODIFIED FOR NGINX v1.24.0) ---

# 1a. Install prerequisites for adding repositories (curl, gpg, etc.)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    software-properties-common curl wget ca-certificates gnupg2 lsb-release

# 1b. Add official Nginx repository
RUN curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor -o /usr/share/keyrings/nginx-archive-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/ubuntu $(lsb_release -cs) nginx" \
    > /etc/apt/sources.list.d/nginx.list

# 1c. Update lists again and install all main packages, pinning Nginx to the desired version
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    # Pin Nginx to version 1.24.0 from the official repository
    nginx=1.24.0-1~jammy \
    # Other packages
    git openssh-server sudo cron nano tar gzip unzip sshpass \
    python3 python3-pip python3-dev build-essential \
    supervisor mysql-server && \
    rm -rf /var/lib/apt/lists/*

# --- 2. Install Go Language Environment ---
RUN wget https://go.dev/dl/go1.24.4.linux-amd64.tar.gz -O /tmp/go.tar.gz && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && rm /tmp/go.tar.gz
ENV PATH="/usr/local/go/bin:${PATH}"

# --- 3. Install Node.js Environment (LTS) ---
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# --- 4. Install PHP 7.4 and Extensions ---
RUN add-apt-repository ppa:ondrej/php -y && apt-get update && \
    apt-get install -y --no-install-recommends \
    php7.4-fpm php7.4-mysql php7.4-gd php7.4-curl php7.4-mbstring php7.4-xml php7.4-zip \
    php7.4-bcmath php7.4-soap php7.4-intl php7.4-readline && \
    rm -rf /var/lib/apt/lists/*

# --- 5. Integrate CloudSaver (FINAL FIX: Rebuild native modules) ---
COPY --from=cloudsaver_stage /app /var/www/html/cloudsaver/
# Remove the incompatible Alpine-compiled modules and rebuild them on Ubuntu
RUN cd /var/www/html/cloudsaver && \
    rm -rf node_modules && \
    npm install --omit=dev

# --- 6. Configure Services ---
COPY supervisord.conf /etc/supervisor/supervisord.conf
RUN mkdir -p /var/log/supervisor /var/www/html/supervisor/conf.d
COPY nginx-maccms.conf /etc/nginx/sites-available/maccms
RUN ln -s /etc/nginx/sites-available/maccms /etc/nginx/sites-enabled/maccms && rm /etc/nginx/sites-enabled/default

# --- FIX for PHP open_basedir Error ---
RUN sed -i 's|;*php_admin_value\[open_basedir\]\s*=\s*.*|;php_admin_value[open_basedir] = none|' /etc/php/7.4/fpm/pool.d/www.conf

# --- FIX for SSH Password Login ---
RUN sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

RUN sed -i 's/;daemonize = yes/daemonize = no/' /etc/php/7.4/fpm/php-fpm.conf
RUN sed -i 's|datadir\s*=\s*/var/lib/mysql|datadir = /var/www/html/mysql_data|' /etc/mysql/mysql.conf.d/mysqld.cnf && \
    sed -i 's|#bind-address\s*=\s*127.0.0.1|bind-address = 127.0.0.1|' /etc/mysql/mysql.conf.d/mysqld.cnf

COPY cron_monitor.sh /usr/local/bin/cron_monitor.sh
RUN chmod +x /usr/local/bin/cron_monitor.sh && \
    mkdir -p /var/www/html/cron

# --- 8. Setup Scripts and Entrypoint ---
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# --- 9. Final Steps ---
EXPOSE 80
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]

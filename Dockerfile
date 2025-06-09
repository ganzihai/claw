# =========================================================================
# STAGE 1: Diagnose the source image's contents
# =========================================================================
FROM jiangrui1994/cloudsaver:latest AS cloudsaver_stage

# --- DIAGNOSTIC COMMAND ---
# This command will run during the build and show us the exact file structure of /app.
# The output will be visible in your terminal.
RUN echo "--- START DIAGNOSIS OF SOURCE IMAGE ---" && \
    ls -lR /app && \
    echo "--- END DIAGNOSIS OF SOURCE IMAGE ---"

# =========================================================================
# STAGE 2: Main build stage
# =========================================================================
FROM ubuntu:22.04

# --- Environment and Arguments ---
ARG DEBIAN_FRONTEND=noninteractive
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8

# --- 1. Install Base Packages & Dependencies ---
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    software-properties-common git openssh-server sudo curl wget cron nano tar gzip unzip sshpass \
    python3 python3-pip nginx supervisor mysql-server && \
    rm -rf /var/lib/apt/lists/*

# --- 2. Install Go Language Environment ---
RUN wget https://go.dev/dl/go1.22.4.linux-amd64.tar.gz -O /tmp/go.tar.gz && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && rm /tmp/go.tar.gz
ENV PATH="/usr/local/go/bin:${PATH}"

# --- 3. Install Node.js Environment (LTS) ---
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/*

# --- 4. Install PHP 7.4 and Extensions ---
RUN add-apt-repository ppa:ondrej/php -y && apt-get update && \
    apt-get install -y --no-install-recommends \
    php7.4-fpm php7.4-mysql php7.4-gd php7.4-curl php7.4-mbstring php7.4-xml php7.4-zip \
    php7.4-bcmath php7.4-soap php7.4-intl php7.4-readline && \
    rm -rf /var/lib/apt/lists/*

# --- 5. Integrate CloudSaver (Copying entire directory) ---
COPY --from=cloudsaver_stage /app /opt/cloudsaver/

# --- 6. Configure Services ---
COPY supervisord.conf /etc/supervisor/supervisord.conf
RUN mkdir -p /var/log/supervisor
COPY nginx-maccms.conf /etc/nginx/sites-available/maccms
RUN ln -s /etc/nginx/sites-available/maccms /etc/nginx/sites-enabled/maccms && rm /etc/nginx/sites-enabled/default
RUN sed -i 's/;daemonize = yes/daemonize = no/' /etc/php/7.4/fpm/php-fpm.conf
RUN sed -i 's|datadir\s*=\s*/var/lib/mysql|datadir = /var/www/html/mysql_data|' /etc/mysql/mysql.conf.d/mysqld.cnf
RUN sed -i 's|#bind-address\s*=\s*127.0.0.1|bind-address = 127.0.0.1|' /etc/mysql/mysql.conf.d/mysqld.cnf

# --- 7. Setup Scripts and Entrypoint ---
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# --- 8. Final Steps ---
EXPOSE 80
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]

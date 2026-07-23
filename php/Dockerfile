# Stage 1: Base system
FROM php:8.3-fpm AS system-base

RUN apt-get update && apt-get install -y --no-install-recommends \
    zsh curl wget unzip git gnupg \
    net-tools iproute2 iputils-ping telnet netcat-traditional \
    bash-completion lsb-release \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Stage 2: Development tooling
FROM system-base AS dev-tools

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc g++ make nodejs npm \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Stage 3: PHP extension libraries
FROM dev-tools AS php-libs

RUN apt-get update && apt-get install -y --no-install-recommends \
    # Libraries for GD, intl and friends
    libfreetype6-dev libjpeg62-turbo-dev libpng-dev libwebp-dev libxpm-dev \
    libxml2-dev libxslt1-dev \
    libicu-dev \
    libonig-dev \
    libzip-dev \
    libbz2-dev \
    libgmp-dev \
    # Libraries for FFI and Imagick
    libffi-dev \
    libmagickwand-dev \
    # Libraries for databases and connections
    libpq-dev \
    libldap2-dev libkrb5-dev \
    libcurl4-openssl-dev libedit-dev zlib1g-dev \
    unixodbc unixodbc-dev libgssapi-krb5-2 librabbitmq-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Stage 4: Terminal productivity tools
FROM php-libs AS terminal-tools

RUN apt-get update && apt-get install -y --no-install-recommends \
    vim nano tmux htop iotop tree mc jq watch \
    figlet lolcat supervisor \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Stage 5: Python environment (for build/analysis scripts)
FROM terminal-tools AS python-env

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install --upgrade pip

ENV PATH="/opt/venv/bin:$PATH"

# Stage: core PHP extensions
FROM python-env AS php-extensions

# Configure and install extensions in a single layer to optimize caching
RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp && \
    docker-php-ext-install -j$(nproc) \
    # Essentials
    bcmath \
    ctype \
    curl \
    exif \
    iconv \
    intl \
    mbstring \
    opcache \
    pcntl \
    sockets \
    xml \
    zip \
    # Databases
    mysqli \
    pdo \
    pdo_mysql \
    pdo_pgsql \
    pgsql \
    # Image manipulation
    gd \
    # Misc
    bz2 \
    calendar \
    ffi \
    ftp \
    gettext \
    gmp \
    soap \
    xsl

# Stage: PECL extensions
FROM php-extensions AS php-pecl

RUN pecl install mongodb redis amqp apcu imagick && \
    docker-php-ext-enable mongodb redis amqp apcu imagick

# Stage: conditional Swoole
FROM php-pecl AS php-swoole

ARG PHP_ENABLE_SWOOLE=false
RUN if [ "$PHP_ENABLE_SWOOLE" = "true" ]; then \
        echo "Installing Swoole..."; \
        pecl install swoole && \
        docker-php-ext-enable swoole; \
        php -m | grep -q swoole && echo "Swoole installed and enabled." \
            || { echo "ERROR: Swoole not found after installation."; exit 1; }; \
    else \
        echo "Swoole disabled (PHP_ENABLE_SWOOLE=false). Skipping."; \
    fi

# ============================================================
# DEV target (final): full development image.
# Keeps ALL the tooling: zsh/Oh My Zsh/p10k, tmux, node,
# python, supervisor, plus the extensions compiled above.
# ============================================================
FROM php-swoole AS final

# Conditional Xdebug (dev image only; never in prod)
ARG PHP_ENABLE_XDEBUG=false
RUN if [ "$PHP_ENABLE_XDEBUG" = "true" ]; then \
        echo "Installing Xdebug..."; \
        pecl install xdebug && \
        docker-php-ext-enable xdebug; \
    else \
        echo "Xdebug disabled (PHP_ENABLE_XDEBUG=false). Skipping."; \
    fi

# PHP config
COPY ./php-dev.ini /usr/local/etc/php/php.ini
COPY ./conf/php-fpm.conf /usr/local/etc/php-fpm.d/www.conf

# Oh My Zsh without overriding the .zshrc
RUN git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git /root/.oh-my-zsh && \
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git /root/.oh-my-zsh/custom/themes/powerlevel10k

# Dotfiles
COPY ./dotfiles/zshrc /root/.zshrc
COPY ./dotfiles/p10k.zsh /root/.p10k.zsh
COPY ./dotfiles/tmux /root/.tmux
COPY ./dotfiles/tmux/tmux.conf /root/.tmux.conf
RUN chmod +x /root/.tmux/scripts/*.sh
COPY ./dotfiles/zsh-custom /root/.zsh-custom

# Composer (official binary — running php in the build segfaults under
# QEMU emulation in multi-arch builds)
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

WORKDIR /var/www

# ============================================================
# PROD target: slim runtime.
# Starts from a clean php:8.3-fpm, installs ONLY runtime libs and
# copies the compiled extensions from the builder stage — no
# toolchain, node, python or terminal tools.
# ============================================================
FROM php:8.3-fpm AS prod

# Runtime counterparts of the -dev packages in php-libs.
# Package names from Debian 13 (trixie), the current php:8.3-fpm base.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libfreetype6 libjpeg62-turbo libpng16-16t64 libwebp7 libxpm4 \
    libxslt1.1 \
    libicu76 \
    libonig5 \
    libzip5 \
    libbz2-1.0 \
    libgmp10 \
    libffi8 \
    libmagickwand-7.q16-10 \
    libpq5 \
    librabbitmq4 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Compiled extensions + enablement inis from the builder
COPY --from=php-swoole /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=php-swoole /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/

# Production config
COPY ./php-prod.ini /usr/local/etc/php/php.ini
COPY ./conf/php-fpm.conf /usr/local/etc/php-fpm.d/www.conf

# Composer (official binary, no toolchain required)
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

# Build-time check that every extension loads with the libs present.
# Native builds only: running php under QEMU emulation (multi-arch
# cross-builds) segfaults; in that case validation is left to smoke/CI.
ARG BUILDARCH
ARG TARGETARCH
RUN if [ "$BUILDARCH" = "$TARGETARCH" ] || [ -z "$BUILDARCH" ]; then \
        php -m > /dev/null && php --version; \
    else \
        echo "Cross-build ($BUILDARCH -> $TARGETARCH): extension validation deferred to smoke/CI."; \
    fi

WORKDIR /var/www

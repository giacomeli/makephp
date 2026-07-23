# Camada 1: Sistema base
FROM php:8.3-fpm AS system-base

RUN apt-get update && apt-get install -y --no-install-recommends \
    zsh curl wget unzip git gnupg \
    net-tools iproute2 iputils-ping telnet netcat-traditional \
    bash-completion lsb-release \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Camada 2: Ferramentas de desenvolvimento
FROM system-base AS dev-tools

RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc g++ make nodejs npm \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Camada 3: Bibliotecas de extensões PHP
FROM dev-tools AS php-libs

RUN apt-get update && apt-get install -y --no-install-recommends \
    # Bibliotecas para extensões GD, intl, e outras
    libfreetype6-dev libjpeg62-turbo-dev libpng-dev libwebp-dev libxpm-dev \
    libxml2-dev libxslt1-dev \
    libicu-dev \
    libonig-dev \
    libzip-dev \
    libbz2-dev \
    libgmp-dev \
    # Bibliotecas para FFI e Imagick
    libffi-dev \
    libmagickwand-dev \
    # Bibliotecas para DBs e Conexões
    libpq-dev \
    libldap2-dev libkrb5-dev \
    libcurl4-openssl-dev libedit-dev zlib1g-dev \
    unixodbc unixodbc-dev libgssapi-krb5-2 librabbitmq-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Camada 4: Ferramentas de produtividade para terminal
FROM php-libs AS terminal-tools

RUN apt-get update && apt-get install -y --no-install-recommends \
    vim nano tmux htop iotop tree mc jq watch \
    figlet lolcat supervisor \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Camada 5: Ambiente Python (para scripts de build/análise)
FROM terminal-tools AS python-env

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/venv && \
    /opt/venv/bin/pip install --upgrade pip

ENV PATH="/opt/venv/bin:$PATH"

# Fase: Extensões PHP padrão
FROM python-env AS php-extensions

# Configura e instala extensões em uma única camada para otimizar o cache
RUN docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp && \
    docker-php-ext-install -j$(nproc) \
    # Essenciais
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
    # Banco de Dados
    mysqli \
    pdo \
    pdo_mysql \
    pdo_pgsql \
    pgsql \
    # Manipulação de Imagem
    gd \
    # Outras
    bz2 \
    calendar \
    ffi \
    ftp \
    gettext \
    gmp \
    soap \
    xsl

# Fase: Extensões PHP via PECL
FROM php-extensions AS php-pecl

# Instala extensões PECL e as habilita
RUN pecl install mongodb redis amqp apcu imagick && \
    docker-php-ext-enable mongodb redis amqp apcu imagick

# Fase: Swoole condicional
FROM php-pecl AS php-swoole

ARG PHP_ENABLE_SWOOLE=false
RUN if [ "$PHP_ENABLE_SWOOLE" = "true" ]; then \
        echo "Instalando Swoole..."; \
        pecl install swoole && \
        docker-php-ext-enable swoole; \
        php -m | grep -q swoole && echo "Swoole instalado e habilitado." \
            || { echo "ERRO: Swoole nao foi encontrado apos a instalacao."; exit 1; }; \
    else \
        echo "Swoole desativado (PHP_ENABLE_SWOOLE=false). Pulando instalacao."; \
    fi

# ============================================================
# Target DEV (final): imagem completa de desenvolvimento.
# Mantem TODAS as ferramentas: zsh/Oh My Zsh/p10k, tmux, node,
# python, supervisor, e as extensoes compiladas acima.
# ============================================================
FROM php-swoole AS final

# Xdebug condicional (apenas na imagem dev; nunca na prod)
ARG PHP_ENABLE_XDEBUG=false
RUN if [ "$PHP_ENABLE_XDEBUG" = "true" ]; then \
        echo "Instalando Xdebug..."; \
        pecl install xdebug && \
        docker-php-ext-enable xdebug; \
    else \
        echo "Xdebug desativado (PHP_ENABLE_XDEBUG=false). Pulando instalacao."; \
    fi

# PHP Config
COPY ./php-dev.ini /usr/local/etc/php/php.ini
COPY ./conf/php-fpm.conf /usr/local/etc/php-fpm.d/www.conf

# Instala Oh My Zsh sem sobrescrever o .zshrc
RUN git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git /root/.oh-my-zsh && \
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git /root/.oh-my-zsh/custom/themes/powerlevel10k

# Dotfiles
COPY ./dotfiles/zshrc /root/.zshrc
COPY ./dotfiles/p10k.zsh /root/.p10k.zsh
COPY ./dotfiles/tmux /root/.tmux
COPY ./dotfiles/tmux/tmux.conf /root/.tmux.conf
RUN chmod +x /root/.tmux/scripts/*.sh
COPY ./dotfiles/zsh-custom /root/.zsh-custom

# Composer (binario oficial — nao executa php no build, o que segfaulta
# sob emulacao QEMU em builds multi-arch)
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

# Diretório padrão
WORKDIR /var/www

# ============================================================
# Target PROD: runtime enxuto.
# Parte do php:8.3-fpm limpo, instala SOMENTE libs de runtime e
# copia as extensoes ja compiladas do estagio builder — sem
# toolchain, node, python ou ferramentas de terminal.
# ============================================================
FROM php:8.3-fpm AS prod

# Runtime das extensoes compiladas (equivalentes non-dev de php-libs).
# Nomes de pacote do Debian 13 (trixie), base do php:8.3-fpm atual.
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

# Extensoes compiladas + inis de ativacao vindos do builder
COPY --from=php-swoole /usr/local/lib/php/extensions/ /usr/local/lib/php/extensions/
COPY --from=php-swoole /usr/local/etc/php/conf.d/ /usr/local/etc/php/conf.d/

# Config de producao
COPY ./php-prod.ini /usr/local/etc/php/php.ini
COPY ./conf/php-fpm.conf /usr/local/etc/php-fpm.d/www.conf

# Composer (binario oficial, sem toolchain)
COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

# Valida no build que todas as extensoes carregam com as libs presentes.
# Apenas em build nativo: executar php sob emulacao QEMU (cross-build
# multi-arch) segfaulta; nesses casos a validacao fica com o smoke/CI.
ARG BUILDARCH
ARG TARGETARCH
RUN if [ "$BUILDARCH" = "$TARGETARCH" ] || [ -z "$BUILDARCH" ]; then \
        php -m > /dev/null && php --version; \
    else \
        echo "Cross-build ($BUILDARCH -> $TARGETARCH): validacao de extensoes adiada para smoke/CI."; \
    fi

WORKDIR /var/www

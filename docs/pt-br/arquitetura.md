# Arquitetura: Visão Geral

Ambiente Docker orquestrado por Makefile para aplicações PHP/Laravel, projetado para servir tanto o desenvolvimento local (macOS/Linux) quanto um host de produção single-node (Debian). O princípio central:

- **A infraestrutura vive neste repositório**: bancos, cache, filas, proxy reverso e emissão de certificados.
- **As aplicações vivem em seus próprios repositórios**: cada app declara uma pasta `container_config/` (Dockerfile, entrypoint, supervisord) e é registrado no `.env` deste projeto por convenção de nomes `<APP>_*`.

---

## Topologia de serviços

```mermaid
%%{init: {'theme':'base','themeVariables':{'primaryColor':'#E3F2FD','primaryTextColor':'#0D47A1','primaryBorderColor':'#1976D2','lineColor':'#546E7A'}}}%%
flowchart LR
    accTitle: Topologia de servicos do makephp
    accDescr: Clientes HTTP chegam ao nginx, que encaminha para php-fpm via FastCGI ou para containers de apps via proxy reverso. Todos os servicos compartilham a rede Docker externa phpdocker-network. O certbot compartilha volumes de certificados com o nginx.

    classDef edge fill:#E3F2FD,stroke:#1976D2
    classDef app fill:#FFF3E0,stroke:#EF6C00
    classDef infra fill:#F1F8E9,stroke:#558B2F
    classDef aux fill:#F3E5F5,stroke:#7B1FA2

    CLIENT["Browser / Cliente"]:::edge

    subgraph NET["Rede externa: phpdocker-network"]
        NGINX["nginx 1.29-alpine"]:::edge
        FPM["php-fpm (PHP 8.x + PECL)"]:::app
        APPS["Containers de apps<br>(modo proxy, ex.: Reverb)"]:::app
        MDB[("MariaDB")]:::infra
        PG[("TimescaleDB pg15")]:::infra
        RD[("Redis 8")]:::infra
        RMQ[("RabbitMQ 4 + management")]:::infra
        MG[("MongoDB 6")]:::infra
        CB["certbot"]:::aux
    end

    CLIENT -- "HTTP :80 / HTTPS :443" --> NGINX
    NGINX -- "fastcgi_pass :9000" --> FPM
    NGINX -- "proxy_pass" --> APPS
    FPM -- "PDO / redis / amqp" --> MDB
    FPM --> RD
    FPM --> RMQ
    APPS --> MDB
    APPS --> RD
    APPS --> RMQ
    CB -- "volumes certbot_certs<br>e certbot_webroot" --> NGINX
```

A rede `phpdocker-network` é **externa** ao compose — precisa existir antes do primeiro `make up`:

```bash
docker network create phpdocker-network
```

Isso permite que containers de apps definidos em outros arquivos compose (ou manualmente) se conectem à mesma rede e resolvam os serviços pelos aliases declarados no `.env` (`MARIADB_ALIASES`, `REDIS_ALIASES`, etc.).

---

## Serviços e exposição de portas

| Serviço | Imagem | Porta no host | Observação |
| --- | --- | --- | --- |
| nginx | `nginx:1.29-alpine` | `NGINX_PORT_HTTP:80`, `NGINX_PORT_HTTPS:443` | Único ponto de entrada público; healthcheck em `/healthz` |
| php-fpm | build local `php/Dockerfile` (target `final`) | — (apenas rede interna) | Base compartilhada para sites em modo `php` |
| mariadb | build local `mariadb/` (`mariadb:12.2`) | `127.0.0.1:MARIADB_PORT` | `my.cnf` tunado; autenticação obrigatória |
| redis | `redis:8-alpine` | `127.0.0.1:REDIS_PORT` | `requirepass` via `.env`; healthcheck autenticado |
| rabbitmq | `rabbitmq:4-management` | `127.0.0.1` (5672 e 15672) | Credenciais via `RABBITMQ_USER`/`RABBITMQ_PASSWORD` |
| postgres-timescale | `timescale/timescaledb:2.28.3-pg15` | `127.0.0.1:POSTGRES_TIMESCALE_PORT` | Séries temporais; healthcheck `pg_isready` |
| mongodb | `mongo:6.0` | `127.0.0.1:MONGODB_PORT` | **Não** sobe no `make up` padrão; root user via `.env` |
| certbot | build local `certbot/` (`certbot:v5.7.0`) | — | Executado sob demanda (`make cert-gen`, `cert-renew`) |

Toda a infraestrutura fica em loopback; apenas o nginx publica em todas as interfaces. `make up` sobe `php-fpm nginx mariadb redis rabbitmq postgres-timescale` — o MongoDB é opcional (`make up mongodb`). Logs de nginx e php-fpm ficam em `./logs/` (criado pelo `make init`).

---

## Imagem PHP multi-stage (dev e prod)

O `php/Dockerfile` encadeia estágios para maximizar o cache de camadas e oferece dois targets finais: `final` (dev, completa) e `prod` (runtime enxuto que copia as extensões compiladas do builder — sem gcc, node, python ou ferramentas de terminal). A versão do PHP é build arg (`PHP_VERSION`, derivada do `PHP_IMAGE_TAG` do `.env`), e 8.3/8.4/8.5 são publicadas em `giacomeli/makephp` (`8.x-dev` / `8.x-prod`, amd64+arm64):

```mermaid
%%{init: {'theme':'base','themeVariables':{'primaryColor':'#E3F2FD','primaryTextColor':'#0D47A1','primaryBorderColor':'#1976D2','lineColor':'#546E7A'}}}%%
flowchart LR
    accTitle: Estagios do build da imagem PHP
    accDescr: Cadeia linear de estagios Docker, do sistema base ate a imagem final com Composer e dotfiles. O estagio de Swoole e condicional por build arg.

    classDef stage fill:#E3F2FD,stroke:#1976D2
    classDef cond fill:#FFF3E0,stroke:#EF6C00
    classDef prod fill:#F1F8E9,stroke:#558B2F

    A["system-base<br>zsh, git, rede"]:::stage --> B["dev-tools<br>gcc, node, npm"]:::stage
    B --> C["php-libs<br>libs de extensoes"]:::stage
    C --> D["terminal-tools<br>vim, tmux, supervisor"]:::stage
    D --> E["python-env<br>venv para scripts"]:::stage
    E --> F["php-extensions<br>gd, intl, pdo_mysql, pdo_pgsql..."]:::stage
    F --> G["php-pecl<br>mongodb, redis, amqp, apcu, imagick"]:::stage
    G --> H["php-swoole<br>condicional: PHP_ENABLE_SWOOLE"]:::cond
    H --> I["final (DEV)<br>Xdebug condicional, Composer,<br>Oh My Zsh, dotfiles"]:::stage
    H -- "COPY extensoes compiladas" --> J["prod<br>php:8.x-fpm limpo + libs de runtime<br>+ php-prod.ini + Composer"]:::prod
```

Pontos de atenção:

- `PHP_ENABLE_SWOOLE=true` e `PHP_ENABLE_XDEBUG=true` no `.env` controlam os estágios condicionais — o `make build` e o compose repassam os build args. Xdebug existe apenas na imagem dev; o modo em runtime vem de `XDEBUG_ENABLE` (env `XDEBUG_MODE`).
- `php.ini` por ambiente: `php/php-dev.ini` (montado no php-fpm local) e `php/php-prod.ini` (embutido no target prod, com `opcache.validate_timestamps=0`).
- A imagem prod valida no build que todas as extensoes carregam (`php -m`).

---

## Camadas de orquestração (Makefile)

O `Makefile` principal carrega o `.env`, define `SED_INPLACE` (compatibilidade macOS/Linux) e inclui três módulos:

| Módulo | Responsabilidade |
| --- | --- |
| `makefiles/php.mk` | Build das imagens (dev/prod), publicação no DockerHub, helpers por container |
| `makefiles/nginx.mk` | Build de apps, geração validada de configs Nginx, ciclo de vida de certificados |
| `makefiles/apps.mk` | `register-app`/`unregister-app` (geração do compose de apps) |
| `makefiles/system.mk` | `init`, `up`/`down`/`restart`/`logs`, `smoke`, `/etc/hosts`, limpeza |

A sintaxe de argumentos varia por alvo (posicional, sufixo com hífen, `name=`) — detalhada em [comandos.md](./comandos.md).

---

## Fluxo de uma requisição PHP

```mermaid
%%{init: {'theme':'base','themeVariables':{'primaryColor':'#E3F2FD','primaryTextColor':'#0D47A1','primaryBorderColor':'#1976D2','lineColor':'#546E7A'}}}%%
sequenceDiagram
    accTitle: Requisicao HTTP a um site PHP
    accDescr: O browser resolve o dominio via /etc/hosts, o nginx casa o server_name com o vhost gerado, consulta o cache FastCGI e encaminha ao php-fpm quando necessario.

    participant B as Browser
    participant N as nginx
    participant F as php-fpm
    participant D as MariaDB/Redis

    B->>N: GET https://meuapp.test (resolvido via /etc/hosts)
    N->>N: casa server_name com vhost em conf.d/
    alt hit no fastcgi_cache
        N-->>B: resposta cacheada (X-FastCGI-Cache: HIT)
    else miss
        N->>F: FastCGI (SCRIPT_FILENAME em /var/www/...)
        F->>D: queries / cache / filas
        D-->>F: dados
        F-->>N: resposta PHP
        N-->>B: resposta (armazenada no cache)
    end
```

O cache FastCGI está habilitado nos templates PHP com bypass automático por cookie de sessão — páginas autenticadas nunca são servidas do cache.

---

## Referências

| Arquivo | Responsabilidade |
| --- | --- |
| `docker-compose.yml` | Definição de todos os serviços, volumes e rede |
| `php/Dockerfile` | Imagem PHP multi-stage |
| `nginx/nginx.conf` | Config global do proxy (gzip, TLS, cache, headers) |
| `Makefile` + `makefiles/*.mk` | Orquestração |
| [nginx-ssl.md](./nginx-ssl.md) | Sistema de templates e certificados |
| [apps.md](./apps.md) | Registro e ciclo de vida de aplicações |
| [producao.md](./producao.md) | Operação no host de produção |
| [comandos.md](./comandos.md) | Referência completa do Makefile |

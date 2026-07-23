# makephp

Ambiente Docker completo para aplicações PHP, orquestrado por Makefile. Um único repositório provê a infraestrutura compartilhada — Nginx, PHP-FPM, MariaDB, Redis, RabbitMQ, TimescaleDB, MongoDB e Certbot — enquanto cada aplicação vive no seu próprio repositório e é plugada por convenção de variáveis no `.env`. Serve tanto o desenvolvimento local (macOS/Linux) quanto um host de produção single-node com HTTPS automatizado.

## Recursos

- Imagem PHP 8.3-FPM em dois sabores: **dev** (extensões + zsh/Oh My Zsh, tmux, node, python, supervisor, Xdebug opcional) e **prod** (runtime enxuto com as mesmas extensões, sem toolchain) — publicadas em [hub.docker.com/u/giacomeli](https://hub.docker.com/u/giacomeli) com suporte a amd64 e arm64.
- Registro de aplicações sem tocar no compose: `make register-app` gera o serviço a partir do `.env`.
- Geração de vhosts Nginx a partir de templates: PHP/Laravel, proxy reverso (websockets/Reverb), estáticos e WordPress, com variantes HTTPS — validados com `nginx -t` antes de recarregar.
- Certificados Let's Encrypt via Certbot em container (webroot) com renovação automática por systemd timer.
- Nginx endurecido: TLS 1.2/1.3, security headers, cache FastCGI com bypass de sessão, catch-all que rejeita hosts e SNI desconhecidos.
- Infraestrutura exposta apenas em loopback; somente o Nginx (80/443) publica para fora. Healthchecks em todos os serviços.
- Projeto de exemplo incluído (`examples/demo-app`) e smoke test de ponta a ponta (`make smoke`).

## Arquitetura

```mermaid
%%{init: {'theme':'base','themeVariables':{'primaryColor':'#E3F2FD','primaryTextColor':'#0D47A1','primaryBorderColor':'#1976D2','lineColor':'#546E7A'}}}%%
flowchart LR
    accTitle: Visao geral do makephp
    accDescr: O nginx recebe todo o trafego e encaminha para o php-fpm via FastCGI ou para containers de apps via proxy; todos os servicos compartilham uma rede Docker externa.

    classDef edge fill:#E3F2FD,stroke:#1976D2
    classDef app fill:#FFF3E0,stroke:#EF6C00
    classDef infra fill:#F1F8E9,stroke:#558B2F

    C["Browser"]:::edge -- "80 / 443" --> N["nginx"]:::edge
    N -- "FastCGI" --> F["php-fpm"]:::app
    N -- "proxy" --> A["apps<br>(repos externos)"]:::app
    F --> I[("MariaDB / Redis / RabbitMQ<br>TimescaleDB / MongoDB")]:::infra
    A --> I
```

Documentação detalhada em [`docs/`](./docs/):

| Documento | Conteúdo |
| --- | --- |
| [docs/arquitetura.md](./docs/arquitetura.md) | Topologia, serviços, portas, imagem PHP multi-stage (dev e prod) |
| [docs/apps.md](./docs/apps.md) | Como registrar e operar aplicações |
| [docs/nginx-ssl.md](./docs/nginx-ssl.md) | Sistema de templates Nginx e ciclo de certificados |
| [docs/comandos.md](./docs/comandos.md) | Referência completa do Makefile e sintaxes de argumento |
| [docs/producao.md](./docs/producao.md) | Deploy, renovação automática de certs e hardening |

## Requisitos

- Docker Engine + Docker Compose v2 (buildx incluso)
- GNU Make
- macOS ou Linux (o Makefile trata a diferença de `sed` automaticamente)

## Começando

```bash
git clone https://github.com/giacomeli/makephp && cd makephp
make init          # cria .env, rede Docker, pastas de log e compose.apps.yml
# edite o .env: LOCAL_DIR e senhas (os "changeme" DEVEM ser trocados)
make build         # imagem PHP base dev (demora na primeira vez)
make up            # sobe nginx, php-fpm, mariadb, redis, rabbitmq, timescaledb
make ps            # confere o estado (healthchecks)
```

O MongoDB não sobe por padrão — `make up mongodb` quando precisar.

Validação completa da stack com o app de exemplo:

```bash
make smoke
```

## Imagens no DockerHub

| Imagem | Conteúdo | Uso |
| --- | --- | --- |
| `giacomeli/makephp:8.3-dev` | Extensões completas + ferramentas de desenvolvimento | Base para containers de app em dev |
| `giacomeli/makephp:8.3-prod` | Mesmas extensões, runtime enxuto | Base para imagens de produção |

```dockerfile
# Dockerfile de um app (ex.: container_config/Dockerfile)
ARG BASE_IMAGE=giacomeli/makephp:8.3-dev
FROM ${BASE_IMAGE}
```

Tags datadas (`8.3-dev-YYYYMMDD`) permitem pinar uma versão exata. Publicação: `make push-php` (multi-arch via buildx).

## Registrando uma aplicação

1. No repositório **do app**: pasta `container_config/` com `Dockerfile`, `entrypoint.sh` e `supervisord.conf` (modelo em [`examples/demo-app/`](./examples/demo-app/)).
1. No `.env` **deste repositório**: bloco de variáveis do app.

    ```dotenv
    MEUAPP_NGINX_MODE=proxy        # php | proxy | html | none
    MEUAPP_CONTAINER_NAME=meuapp
    MEUAPP_PROJECT_PATH=/caminho/absoluto/para/meuapp
    MEUAPP_DOCKER_PATH=/var/www
    MEUAPP_ALIASES="meuapp.test"
    MEUAPP_PORT=8000
    ```

1. Registrar e subir:

    ```bash
    make register-app meuapp       # gera o servico no compose.apps.yml
    make build-app meuapp          # build + vhost nginx + reload validado
    make up meuapp
    sudo make hosts-add-meuapp     # aliases no /etc/hosts
    ```

Guia completo (modos, root do vhost, como os apps enxergam a infra) em [docs/apps.md](./docs/apps.md).

## Comandos essenciais

| Comando | Ação |
| --- | --- |
| `make init` | Onboarding: .env, rede, logs, compose.apps.yml |
| `make up` / `make down` | Sobe / para a infraestrutura (down preserva os vhosts) |
| `make register-app <app>` / `make build-app <app>` | Registra e builda um app |
| `make shell-<container>` | Shell zsh dentro do container |
| `make artisan-<container>` / `make composer-<container>` | Laravel artisan / Composer |
| `make nginx-list` | Inventário de sites e status SSL |
| `make cert-gen domain=exemplo.com` | Emite certificado Let's Encrypt |
| `make enable-ssl name=site` | Migra um vhost para HTTPS |
| `make smoke` | Valida a stack de ponta a ponta |
| `make clean-confs` | Remove apenas vhosts gerados (preserva os manuais) |

Alvos por app usam **sufixo com hífen** (`make shell-meuapp`); `build-app`, `up`, `register-app` e `unregister-app` aceitam o nome como argumento posicional. Referência completa em [docs/comandos.md](./docs/comandos.md).

## Produção

O mesmo repositório opera um host de produção: `.env` com `NGINX_PORT_HTTP=80` e senhas reais, certificados via `make cert-gen` + `make enable-ssl`, renovação automática com os units de `systemd/`, e imagem `8.3-prod` como base dos apps. Checklist de hardening e notas de migração em [docs/producao.md](./docs/producao.md).

## Licença

[MIT](./LICENSE)

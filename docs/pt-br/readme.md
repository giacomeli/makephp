# makephp

Ambiente Docker completo para aplicações PHP, orquestrado por Makefile. Um único repositório provê a infraestrutura compartilhada — Nginx, PHP-FPM, MariaDB, Redis, RabbitMQ, TimescaleDB, MongoDB e Certbot — enquanto cada aplicação vive no seu próprio repositório e é plugada por convenção de variáveis no `.env`. Serve tanto o desenvolvimento local (macOS/Linux) quanto um host de produção single-node com HTTPS automatizado.

Documentação: **English** ([readme principal](../../readme.md) e [`docs/`](../)) | **Português** (esta pasta)

## Recursos

- Imagem PHP 8.3-FPM em dois sabores: **dev** (extensões + zsh/Oh My Zsh, tmux, node, python, supervisor, Xdebug opcional) e **prod** (runtime enxuto com as mesmas extensões, sem toolchain) — publicadas em [hub.docker.com/u/giacomeli](https://hub.docker.com/u/giacomeli) com suporte a amd64 e arm64.
- Registro de aplicações sem tocar no compose: `make register-app` gera o serviço a partir do `.env`.
- Geração de vhosts Nginx a partir de templates: PHP/Laravel, proxy reverso (websockets/Reverb), estáticos e WordPress, com variantes HTTPS — validados com `nginx -t` antes de recarregar.
- Certificados Let's Encrypt via Certbot em container (webroot) com renovação automática por systemd timer.
- Nginx endurecido: TLS 1.2/1.3, security headers, cache FastCGI com bypass de sessão, catch-all que rejeita hosts e SNI desconhecidos.
- Infraestrutura exposta apenas em loopback; somente o Nginx (80/443) publica para fora. Healthchecks em todos os serviços.
- Projeto de exemplo incluído (`examples/demo-app`) e smoke test de ponta a ponta (`make smoke`).

## Documentação detalhada

| Documento | Conteúdo |
| --- | --- |
| [arquitetura.md](./arquitetura.md) | Topologia, serviços, portas, imagem PHP multi-stage (dev e prod) |
| [apps.md](./apps.md) | Como registrar e operar aplicações |
| [nginx-ssl.md](./nginx-ssl.md) | Sistema de templates Nginx e ciclo de certificados |
| [comandos.md](./comandos.md) | Referência completa do Makefile e sintaxes de argumento |
| [producao.md](./producao.md) | Deploy, renovação automática de certs e hardening |

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

O MongoDB não sobe por padrão — `make up mongodb` quando precisar. Validação completa da stack: `make smoke`.

## Imagens no DockerHub

| Imagem | Conteúdo | Uso |
| --- | --- | --- |
| `giacomeli/makephp:8.3-dev` | Extensões completas + ferramentas de desenvolvimento | Base para containers de app em dev |
| `giacomeli/makephp:8.3-prod` | Mesmas extensões, runtime enxuto | Base para imagens de produção |

Tags datadas (`8.3-dev-YYYYMMDD`) permitem pinar uma versão exata. Publicação: `make push-php` (multi-arch via buildx).

## Registrando uma aplicação

1. No repositório **do app**: pasta `container_config/` com `Dockerfile`, `entrypoint.sh` e `supervisord.conf` (modelo em [`examples/demo-app/`](../../examples/demo-app/)).
1. No `.env` **deste repositório**: bloco de variáveis do app (`MEUAPP_NGINX_MODE`, `MEUAPP_CONTAINER_NAME`, `MEUAPP_PROJECT_PATH`, `MEUAPP_DOCKER_PATH`, `MEUAPP_ALIASES`, `MEUAPP_PORT`).
1. Registrar e subir:

    ```bash
    make register-app meuapp       # gera o servico no compose.apps.yml
    make build-app meuapp          # build + vhost nginx + reload validado
    make up meuapp
    sudo make hosts-add-meuapp     # aliases no /etc/hosts
    ```

Guia completo em [apps.md](./apps.md). Alvos por app usam **sufixo com hífen** (`make shell-meuapp`); `build-app`, `up`, `register-app` e `unregister-app` aceitam o nome como argumento posicional — referência em [comandos.md](./comandos.md).

## Produção

O mesmo repositório opera um host de produção: `.env` com `NGINX_PORT_HTTP=80` e senhas reais, certificados via `make cert-gen` + `make enable-ssl`, renovação automática com os units de `systemd/`, e imagem `8.3-prod` como base dos apps. Checklist de hardening e notas de migração em [producao.md](./producao.md).

## Licença

[MIT](../../LICENSE)

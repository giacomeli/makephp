# Referência de Comandos (Makefile)

Todos os alvos definidos em `Makefile` e `makefiles/*.mk` (`php.mk`, `nginx.mk`, `apps.mk`, `system.mk`), com a sintaxe que de fato funciona. `make` sem argumentos imprime o help; um alvo desconhecido gera aviso em vez de falhar em silêncio.

---

## As três sintaxes de argumento

| Sintaxe | Exemplo | Vale para |
| --- | --- | --- |
| Posicional (`make alvo nome`) | `make build-app demo-app` | `build-app`, `up`, `register-app`, `unregister-app` |
| Sufixo com hífen (`make alvo-nome`) | `make shell-demo-app` | `shell-`, `artisan-`, `composer-`, `queue-`, `reload-`, `hosts-add-`, `hosts-remove-` |
| Variáveis (`make alvo chave=valor`) | `make enable-ssl name=site` | `nginx-conf`, `nginx-html-conf`, `wordpress-conf`, `enable-ssl`, `cert-gen`, `cert-gen-www` |

As formas nuas dos alvos de sufixo (`make shell demo-app`) são stubs que explicam a forma correta e saem com código 1. Para `shell`/`artisan`/`composer`/`queue`, o sufixo é o **nome do container** (vai direto num `docker exec`).

---

## Onboarding e build

| Comando | O que faz |
| --- | --- |
| `make init` | Cria `.env` (do example), rede `phpdocker-network`, `logs/`, `compose.apps.yml` stub — idempotente |
| `make build` | Imagem PHP base **dev** (`--target final`); a versão do PHP é derivada do `PHP_IMAGE_TAG` (override com `PHP_VERSION=8.x`); respeita `PHP_ENABLE_SWOOLE` e `PHP_ENABLE_XDEBUG`; `NO_CACHE=1` ignora cache |
| `make build-prod` | Imagem PHP **prod** enxuta (`--target prod`), tag `<nome>:<versao>-prod` |
| `make rebuild-php` | `docker compose build --no-cache php-fpm` |

## Ciclo de vida

| Comando | O que faz |
| --- | --- |
| `make up` | Sobe a infraestrutura core (mongodb fica de fora — `make up mongodb`) |
| `make up <app>` | Regenera o vhost do app e sobe só ele |
| `make down` | Para os containers; **preserva** os vhosts de `nginx/conf.d/` |
| `make restart` | Reinicia todos os containers |
| `make reload-<app>` | Reinicia um container específico |
| `make logs` / `make ps` | Logs / estado (com healthchecks) |

## Apps

| Comando | O que faz |
| --- | --- |
| `make register-app <app>` | Gera o serviço do app no `compose.apps.yml` a partir do `.env` (idempotente) |
| `make unregister-app <app>` | Remove o serviço (marcadores `# app:<nome>:begin/end`) |
| `make build-app <app>` | Builda o container, gera o vhost pelo `NGINX_MODE`, valida com `nginx -t` e recarrega |
| `make shell-<container>` | zsh dentro do container |
| `make artisan-<container>` / `make composer-<container>` / `make queue-<container>` | Helpers Laravel |

## Nginx

| Comando | O que faz |
| --- | --- |
| `make nginx-list` | Tabela de vhosts com domínio, porta, SSL e root |
| `make nginx-templates` | Lista os templates |
| `make nginx-conf template=<tpl> name=<site> [domain=] [root=] [php_upstream=] [port=]` | Gera vhost de qualquer template (aborta se sobrar placeholder) |
| `make nginx-html-conf name=<site> [domain=] [root=]` | Atalho para o template `html` |
| `make wordpress-conf name=<site> [domain=] [root=]` | Vhost WordPress HTTP |
| `make clean-confs` | Remove **apenas** vhosts com a sentinela `# generated-by: makephp`; preserva os manuais |
| `make nginx-reload-safe` | Valida (`nginx -t`) e recarrega; em conf inválida aborta sem derrubar o nginx |

## SSL / Certificados

| Comando | O que faz |
| --- | --- |
| `make cert-gen domain=exemplo.com` | Emite certificado Let's Encrypt (webroot); aceita `domains="a.com b.com"` |
| `make cert-gen-www domain=exemplo.com` | Emite para o domínio + `www.` |
| `make enable-ssl name=<site> [root=] [domain=] [cert_domain=] [php_upstream=] [template=]` | Troca o vhost pelo template HTTPS preservando a config atual |
| `make cert-renew` | Renova certificados e **recarrega o nginx** |

Requer `CERTBOT_EMAIL` no `.env`; `CERTBOT_STAGING=1` usa o ambiente de teste do Let's Encrypt.

## Validação e publicação

| Comando | O que faz |
| --- | --- |
| `make smoke` | Teste de fumaça completo: sobe a stack, registra/builda o `demo-app` e valida os modos proxy, php e html via curl + `nginx -t` |
| `make push-php [PHP_VERSION=8.x]` | Publica `giacomeli/makephp:<versao>-dev` e `:<versao>-prod` multi-arch (amd64+arm64) no DockerHub, com tags datadas — requer `docker login` |
| `make push-php-all` | Publica todas as versões de `PHP_VERSIONS` (8.3 8.4 8.5), limpando o cache do buildx entre versões |

## DNS local

| Comando | O que faz |
| --- | --- |
| `sudo make hosts-add-<app>` | Adiciona os `<APP>_ALIASES` ao `/etc/hosts` |
| `sudo make hosts-remove-<app>` | Remove os aliases (match ancorado, não afeta hosts parecidos) |

## Limpeza

| Comando | O que faz |
| --- | --- |
| `make clean-images` | Remove a imagem PHP e imagens dangling |
| `make clean-cache` | `docker builder prune` + `docker volume prune` |
| `make clean-all` | Ambos |

---

## Verificação manual

```bash
make smoke                                   # validacao completa de ponta a ponta
docker compose config -q                     # compose valido e .env completo
docker compose exec nginx nginx -t           # sintaxe dos vhosts
make ps                                      # estado + healthchecks
docker compose logs nginx --tail 50          # erros de subida
```

O CI (`.github/workflows/ci.yml`) roda automaticamente: compose config, geração de vhosts + `nginx -t`, hadolint, shellcheck e build do target prod.

---

## Referências

| Arquivo | Alvos |
| --- | --- |
| `Makefile` | `help`, catch-all com aviso, variáveis globais |
| `makefiles/php.mk` | `build`, `build-prod`, `rebuild-php`, `push-php`, helpers de container |
| `makefiles/nginx.mk` | `build-app`, `nginx-*`, `wordpress-conf`, `enable-ssl`, `cert-*` |
| `makefiles/apps.mk` | `register-app`, `unregister-app` |
| `makefiles/system.mk` | `init`, `up`, `down`, `clean-confs`, `smoke`, `hosts-*`, `clean-*` |

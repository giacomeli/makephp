# Command Reference (Makefile)

Every target defined in `Makefile` and `makefiles/*.mk` (`php.mk`, `nginx.mk`, `apps.mk`, `system.mk`), with the syntax that actually works. `make` with no arguments prints the help; an unknown target prints a warning instead of failing silently.

---

## The three argument syntaxes

| Syntax | Example | Applies to |
| --- | --- | --- |
| Positional (`make target name`) | `make build-app demo-app` | `build-app`, `up`, `register-app`, `unregister-app` |
| Dash suffix (`make target-name`) | `make shell-demo-app` | `shell-`, `artisan-`, `composer-`, `queue-`, `reload-`, `hosts-add-`, `hosts-remove-` |
| Variables (`make target key=value`) | `make enable-ssl name=site` | `nginx-conf`, `nginx-html-conf`, `wordpress-conf`, `enable-ssl`, `cert-gen`, `cert-gen-www` |

The bare forms of the suffixed targets (`make shell demo-app`) are stubs that explain the correct form and exit with code 1. For `shell`/`artisan`/`composer`/`queue`, the suffix is the **container name** (it goes straight into `docker exec`).

---

## Onboarding and builds

| Command | What it does |
| --- | --- |
| `make init` | Creates `.env` (from the example), the `phpdocker-network` network, `logs/` and the `compose.apps.yml` stub — idempotent |
| `make build` | **Dev** PHP base image (`--target final`); the PHP version is derived from `PHP_IMAGE_TAG` (override with `PHP_VERSION=8.x`); honors `PHP_ENABLE_SWOOLE` and `PHP_ENABLE_XDEBUG`; `NO_CACHE=1` skips cache |
| `make build-prod` | Slim **prod** PHP image (`--target prod`), tagged `<name>:<version>-prod` |
| `make rebuild-php` | `docker compose build --no-cache php-fpm` |

## Lifecycle

| Command | What it does |
| --- | --- |
| `make up` | Starts the core infrastructure (mongodb stays out — `make up mongodb`) |
| `make up <app>` | Regenerates the app vhost and starts only that app |
| `make down` | Stops containers; **preserves** the vhosts in `nginx/conf.d/` |
| `make restart` | Restarts all containers |
| `make reload-<app>` | Restarts a single container |
| `make logs` / `make ps` | Logs / status (with healthchecks) |

## Apps

| Command | What it does |
| --- | --- |
| `make register-app <app>` | Generates the app service in `compose.apps.yml` from `.env` (idempotent) |
| `make unregister-app <app>` | Removes the service (via the `# app:<name>:begin/end` markers) |
| `make build-app <app>` | Builds the container, generates the vhost for its `NGINX_MODE`, validates with `nginx -t` and reloads |
| `make shell-<container>` | zsh inside the container |
| `make artisan-<container>` / `make composer-<container>` / `make queue-<container>` | Laravel helpers |

## Nginx

| Command | What it does |
| --- | --- |
| `make nginx-list` | Vhost table with domain, port, SSL and root |
| `make nginx-templates` | Lists the templates |
| `make nginx-conf template=<tpl> name=<site> [domain=] [root=] [php_upstream=] [port=]` | Generates a vhost from any template (aborts if placeholders remain) |
| `make nginx-html-conf name=<site> [domain=] [root=]` | Shortcut for the `html` template |
| `make wordpress-conf name=<site> [domain=] [root=]` | WordPress HTTP vhost |
| `make clean-confs` | Removes **only** vhosts carrying the `# generated-by: makephp` sentinel; preserves manual ones |
| `make nginx-reload-safe` | Validates (`nginx -t`) and reloads; on invalid config aborts without taking nginx down |

## SSL / Certificates

| Command | What it does |
| --- | --- |
| `make cert-gen domain=example.com` | Issues a Let's Encrypt certificate (webroot); accepts `domains="a.com b.com"` |
| `make cert-gen-www domain=example.com` | Issues for the domain + `www.` |
| `make enable-ssl name=<site> [root=] [domain=] [cert_domain=] [php_upstream=] [template=]` | Switches the vhost to the HTTPS template, preserving the current config |
| `make cert-renew` | Renews certificates and **reloads nginx** |

Requires `CERTBOT_EMAIL` in `.env`; `CERTBOT_STAGING=1` uses the Let's Encrypt staging environment.

## Validation and publishing

| Command | What it does |
| --- | --- |
| `make smoke` | Full smoke test: brings the stack up, registers/builds the `demo-app` and validates the proxy, php and html modes via curl + `nginx -t` |
| `make push-php [PHP_VERSION=8.x]` | Publishes `giacomeli/makephp:<version>-dev` and `:<version>-prod` multi-arch (amd64+arm64) to DockerHub, with dated tags — requires `docker login` |
| `make push-php-all` | Publishes every version in `PHP_VERSIONS` (8.3 8.4 8.5), pruning the buildx cache between versions |

## Local DNS

| Command | What it does |
| --- | --- |
| `sudo make hosts-add-<app>` | Adds the `<APP>_ALIASES` to `/etc/hosts` |
| `sudo make hosts-remove-<app>` | Removes the aliases (anchored match, does not touch similar hosts) |

## Cleanup

| Command | What it does |
| --- | --- |
| `make clean-images` | Removes the PHP image and dangling images |
| `make clean-cache` | `docker builder prune` + `docker volume prune` |
| `make clean-all` | Both |

---

## Manual verification

```bash
make smoke                                   # full end-to-end validation
docker compose config -q                     # valid compose and complete .env
docker compose exec nginx nginx -t           # vhost syntax
make ps                                      # status + healthchecks
docker compose logs nginx --tail 50          # startup errors
```

CI (`.github/workflows/ci.yml`) runs automatically: compose config, vhost rendering + `nginx -t`, hadolint, shellcheck and the prod target build.

---

## References

| File | Targets |
| --- | --- |
| `Makefile` | `help`, warning catch-all, global variables |
| `makefiles/php.mk` | `build`, `build-prod`, `rebuild-php`, `push-php`, container helpers |
| `makefiles/nginx.mk` | `build-app`, `nginx-*`, `wordpress-conf`, `enable-ssl`, `cert-*` |
| `makefiles/apps.mk` | `register-app`, `unregister-app` |
| `makefiles/system.mk` | `init`, `up`, `down`, `clean-confs`, `smoke`, `hosts-*`, `clean-*` |

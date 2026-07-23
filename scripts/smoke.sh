#!/usr/bin/env bash
# Smoke test do makephp: valida a stack de ponta a ponta com examples/demo-app.
# Modos validados: proxy (container proprio), php (php-fpm compartilhado) e html.
# Uso: make smoke (ou bash scripts/smoke.sh)
set -uo pipefail

cd "$(cd "$(dirname "$0")/.." && pwd)" || exit 1

PASS=0
FAIL=0
note() { printf '\n== %s\n' "$*"; }
ok()   { echo "   ok: $*"; PASS=$((PASS + 1)); }
bad()  { echo "   FALHA: $*"; FAIL=$((FAIL + 1)); }
die()  { echo "SMOKE FAIL: $*"; exit 1; }

envval() { grep -m1 "^$1=" .env | cut -d= -f2- | tr -d '"'; }

# curl com retry: o reload do nginx e assincrono, a primeira tentativa pode
# pegar a troca de workers.
curl_retry() {
    url_host=$1; url=$2; pattern=$3
    for _ in 1 2 3 4 5; do
        if curl -fsS --resolve "$url_host" "$url" 2>/dev/null | grep -q "$pattern"; then
            return 0
        fi
        sleep 2
    done
    return 1
}

[ -f .env ] || die ".env ausente — rode make init"
PORT=$(envval NGINX_PORT_HTTP); PORT=${PORT:-8099}
LOCAL_DIR=$(envval LOCAL_DIR)
DPP=$(envval DOCKER_PROJECT_PATH); DPP=${DPP:-/var/www}

note "make init (idempotente)"
make init >/dev/null || die "make init falhou"

note "sobe infraestrutura core"
make up >/dev/null || die "make up falhou"

note "espera healthchecks (ate 150s)"
deadline=$((SECONDS + 150))
for c in $(docker compose ps --format '{{.Name}}'); do
    while :; do
        st=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$c" 2>/dev/null || echo missing)
        if [ "$st" = "healthy" ] || [ "$st" = "none" ]; then
            break
        fi
        if [ "$SECONDS" -gt "$deadline" ]; then
            die "container $c nao ficou healthy (status: $st)"
        fi
        sleep 3
    done
done
ok "todos os containers com healthcheck estao healthy"

note "modo proxy: register-app + build-app + up demo-app"
make register-app demo-app >/dev/null || die "register-app falhou"
make build-app demo-app || die "build-app falhou"
make up demo-app >/dev/null || die "up demo-app falhou"
sleep 3
if curl_retry "demo-app.test:$PORT:127.0.0.1" \
        "http://demo-app.test:$PORT/?format=json" '"status": *"ok"'; then
    ok "modo proxy responde HTTP 200 com status ok"
else
    bad "modo proxy nao respondeu (http://demo-app.test:$PORT)"
fi

note "modos php e html (php-fpm compartilhado e estatico)"
case "$PWD" in
    "$LOCAL_DIR"/*)
        REL=${PWD#"$LOCAL_DIR"/}
        ROOT="$DPP/$REL/examples/demo-app/public"
        make nginx-conf template=php name=smoke-php domain=smoke-php.test root="$ROOT" >/dev/null \
            || die "geracao do vhost php falhou"
        make nginx-html-conf name=smoke-html domain=smoke-html.test root="$ROOT" >/dev/null \
            || die "geracao do vhost html falhou"
        make nginx-reload-safe || die "nginx reprovou os vhosts de smoke"
        if curl_retry "smoke-php.test:$PORT:127.0.0.1" \
                "http://smoke-php.test:$PORT/?format=json" '"sapi": *"fpm-fcgi"'; then
            ok "modo php executa via php-fpm (sapi fpm-fcgi)"
        else
            bad "modo php nao respondeu via php-fpm"
        fi
        if curl_retry "smoke-html.test:$PORT:127.0.0.1" \
                "http://smoke-html.test:$PORT/" "makephp demo-app"; then
            ok "modo html serve o estatico"
        else
            bad "modo html nao respondeu"
        fi
        ;;
    *)
        echo "   aviso: repositorio fora de LOCAL_DIR ($LOCAL_DIR) — modos php/html pulados"
        ;;
esac

note "validacoes finais"
if docker compose exec -T nginx nginx -t >/dev/null 2>&1; then
    ok "nginx -t"
else
    bad "nginx -t reprovou"
fi
if grep -R '__[A-Z_]*__' nginx/conf.d/ >/dev/null 2>&1; then
    bad "placeholders nao resolvidos em nginx/conf.d/"
else
    ok "nenhum placeholder remanescente"
fi

note "limpeza dos vhosts de smoke"
rm -f nginx/conf.d/smoke-php.conf nginx/conf.d/smoke-html.conf
make nginx-reload-safe >/dev/null 2>&1 || true
echo "   (demo-app segue registrado e rodando para inspecao)"

echo ""
if [ "$FAIL" -eq 0 ]; then
    echo "SMOKE OK ($PASS verificacoes)"
else
    echo "SMOKE FAIL ($FAIL falha(s), $PASS ok)"
    exit 1
fi

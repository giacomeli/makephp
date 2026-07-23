#!/usr/bin/env bash
# makephp smoke test: validates the stack end to end using examples/demo-app.
# Modes covered: proxy (own container), php (shared php-fpm) and html.
# Usage: make smoke (or bash scripts/smoke.sh)
set -uo pipefail

cd "$(cd "$(dirname "$0")/.." && pwd)" || exit 1

PASS=0
FAIL=0
note() { printf '\n== %s\n' "$*"; }
ok()   { echo "   ok: $*"; PASS=$((PASS + 1)); }
bad()  { echo "   FAIL: $*"; FAIL=$((FAIL + 1)); }
die()  { echo "SMOKE FAIL: $*"; exit 1; }

envval() { grep -m1 "^$1=" .env | cut -d= -f2- | tr -d '"'; }

# curl with retries: nginx reloads are asynchronous, the first attempt may hit
# the worker handover.
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

[ -f .env ] || die ".env missing — run make init"
PORT=$(envval NGINX_PORT_HTTP); PORT=${PORT:-8099}
LOCAL_DIR=$(envval LOCAL_DIR)
DPP=$(envval DOCKER_PROJECT_PATH); DPP=${DPP:-/var/www}

note "make init (idempotent)"
make init >/dev/null || die "make init failed"

note "starting core infrastructure"
make up >/dev/null || die "make up failed"

note "waiting for healthchecks (up to 150s)"
deadline=$((SECONDS + 150))
for c in $(docker compose ps --format '{{.Name}}'); do
    while :; do
        st=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$c" 2>/dev/null || echo missing)
        if [ "$st" = "healthy" ] || [ "$st" = "none" ]; then
            break
        fi
        if [ "$SECONDS" -gt "$deadline" ]; then
            die "container $c did not become healthy (status: $st)"
        fi
        sleep 3
    done
done
ok "all containers with healthchecks are healthy"

note "proxy mode: register-app + build-app + up demo-app"
make register-app demo-app >/dev/null || die "register-app failed"
make build-app demo-app || die "build-app failed"
make up demo-app >/dev/null || die "up demo-app failed"
sleep 3
if curl_retry "demo-app.test:$PORT:127.0.0.1" \
        "http://demo-app.test:$PORT/?format=json" '"status": *"ok"'; then
    ok "proxy mode answers HTTP 200 with status ok"
else
    bad "proxy mode did not answer (http://demo-app.test:$PORT)"
fi

note "php and html modes (shared php-fpm and static)"
case "$PWD" in
    "$LOCAL_DIR"/*)
        REL=${PWD#"$LOCAL_DIR"/}
        ROOT="$DPP/$REL/examples/demo-app/public"
        make nginx-conf template=php name=smoke-php domain=smoke-php.test root="$ROOT" >/dev/null \
            || die "php vhost generation failed"
        make nginx-html-conf name=smoke-html domain=smoke-html.test root="$ROOT" >/dev/null \
            || die "html vhost generation failed"
        make nginx-reload-safe || die "nginx rejected the smoke vhosts"
        if curl_retry "smoke-php.test:$PORT:127.0.0.1" \
                "http://smoke-php.test:$PORT/?format=json" '"sapi": *"fpm-fcgi"'; then
            ok "php mode runs through php-fpm (sapi fpm-fcgi)"
        else
            bad "php mode did not answer through php-fpm"
        fi
        if curl_retry "smoke-html.test:$PORT:127.0.0.1" \
                "http://smoke-html.test:$PORT/" "makephp demo-app"; then
            ok "html mode serves the static file"
        else
            bad "html mode did not answer"
        fi
        ;;
    *)
        echo "   warning: repository outside LOCAL_DIR ($LOCAL_DIR) — php/html modes skipped"
        ;;
esac

note "final validations"
if docker compose exec -T nginx nginx -t >/dev/null 2>&1; then
    ok "nginx -t"
else
    bad "nginx -t failed"
fi
if grep -R '__[A-Z_]*__' nginx/conf.d/ >/dev/null 2>&1; then
    bad "unresolved placeholders in nginx/conf.d/"
else
    ok "no leftover placeholders"
fi

note "cleaning up smoke vhosts"
rm -f nginx/conf.d/smoke-php.conf nginx/conf.d/smoke-html.conf
make nginx-reload-safe >/dev/null 2>&1 || true
echo "   (demo-app stays registered and running for inspection)"

echo ""
if [ "$FAIL" -eq 0 ]; then
    echo "SMOKE OK ($PASS checks)"
else
    echo "SMOKE FAIL ($FAIL failure(s), $PASS ok)"
    exit 1
fi

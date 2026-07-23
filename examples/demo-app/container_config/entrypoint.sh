#!/usr/bin/env bash
# Entrypoint do demo-app: delega ao supervisord, que mantem o php -S no ar.
set -euo pipefail

exec supervisord -n -c /etc/supervisor/supervisord.conf

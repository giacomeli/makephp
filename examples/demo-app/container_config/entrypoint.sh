#!/usr/bin/env bash
# demo-app entrypoint: delegates to supervisord, which keeps php -S running.
set -euo pipefail

exec supervisord -n -c /etc/supervisor/supervisord.conf

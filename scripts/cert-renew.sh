#!/usr/bin/env bash
# Renews Let's Encrypt certificates and reloads nginx (via make cert-renew).
# Executed by the certbot-renew.timer systemd unit (twice a day).
# Logs: journalctl -u certbot-renew.service
#
# The project directory comes from PHPDOCKER_DIR (set in the systemd unit);
# without the variable, it falls back to this script's parent directory.
set -uo pipefail

PHPDOCKER_DIR="${PHPDOCKER_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$PHPDOCKER_DIR" || exit 1

make cert-renew
rc=$?
echo "cert-renew finished (exit=$rc)"
exit $rc

#!/usr/bin/env bash
# Renova certificados Let's Encrypt e recarrega o nginx (via make cert-renew).
# Executado pelo systemd timer certbot-renew.timer (2x/dia).
# Logs: journalctl -u certbot-renew.service
#
# O diretorio do projeto vem de PHPDOCKER_DIR (definido no unit systemd);
# sem a variavel, assume o diretorio pai deste script.
set -uo pipefail

PHPDOCKER_DIR="${PHPDOCKER_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$PHPDOCKER_DIR" || exit 1

make cert-renew
rc=$?
echo "cert-renew finalizado (exit=$rc)"
exit $rc

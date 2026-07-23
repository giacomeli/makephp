#!/bin/bash

WORKDIR="$1"
CONFIG_FILE="$WORKDIR/tmonitor.conf"

if [ ! -d "$WORKDIR" ]; then
  echo "Erro: diretório '$WORKDIR' não encontrado."
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Erro: arquivo de configuração '$CONFIG_FILE' não encontrado."
  exit 1
fi

# Carrega o .conf
source "$CONFIG_FILE"

# SESSION_NAME default
SESSION_NAME="${SESSION_NAME:-monitoring}"

# Verifica comandos
if [ -z "$CMD1" ] || [ -z "$CMD2" ] || [ -z "$CMD3" ]; then
  echo "Erro: CMD1, CMD2 e CMD3 precisam estar definidos em $CONFIG_FILE"
  exit 1
fi

# Captura os 3 primeiros panes (superiores)
PANES_TOP=($(tmux list-panes -t "$SESSION_NAME" -F "#{pane_id}" | head -n 3))

# Interrompe os comandos (Ctrl+C)
tmux send-keys -t "${PANES_TOP[0]}" C-c
tmux send-keys -t "${PANES_TOP[1]}" C-c
tmux send-keys -t "${PANES_TOP[2]}" C-c

# Reenvia os comandos atualizados
tmux send-keys -t "${PANES_TOP[0]}" "cd '$WORKDIR'" C-m "$CMD1" C-m
tmux send-keys -t "${PANES_TOP[1]}" "cd '$WORKDIR'" C-m "$CMD2" C-m
tmux send-keys -t "${PANES_TOP[2]}" "cd '$WORKDIR'" C-m "$CMD3" C-m

# Foca o pane de baixo
tmux select-pane -t "$SESSION_NAME":0.3

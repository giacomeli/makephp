#!/bin/bash

if [ -z "$1" ]; then
  echo "Uso: $0 /caminho/do/diretorio"
  exit 1
fi

WORKDIR="$1"
CONFIG_FILE="$WORKDIR/tmonitor.conf"

if [ ! -d "$WORKDIR" ]; then
  echo "Erro: diretório '$WORKDIR' não encontrado."
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "Erro: arquivo de configuração '$CONFIG_FILE' não encontrado."
  echo "Crie um arquivo $CONFIG_FILE com as variáveis CMD1, CMD2, CMD3 e opcionalmente SESSION_NAME."
  exit 1
fi

source "$CONFIG_FILE"
SESSION_NAME="${SESSION_NAME:-monitoring}"

if [ -z "$CMD1" ] || [ -z "$CMD2" ] || [ -z "$CMD3" ]; then
  echo "Erro: CMD1, CMD2 e CMD3 precisam estar definidos em $CONFIG_FILE"
  exit 1
fi

# Mata a sessão anterior, se existir
tmux has-session -t "$SESSION_NAME" 2>/dev/null && tmux kill-session -t "$SESSION_NAME"

# Cria nova sessão (pane 0)
tmux new-session -d -s "$SESSION_NAME" -c "$WORKDIR"

# Split vertical (pane 1 embaixo)
tmux split-window -v -p 30 -c "$WORKDIR"

# Volta pra cima (pane 0) e faz dois splits horizontais (panes 2 e 3)
tmux select-pane -U
tmux split-window -h -c "$WORKDIR"
tmux select-pane -R
tmux split-window -h -c "$WORKDIR"

# Envia os comandos definidos no .conf
tmux send-keys -t "$SESSION_NAME":0.0 "$CMD1" C-m
tmux send-keys -t "$SESSION_NAME":0.1 "$CMD2" C-m
tmux send-keys -t "$SESSION_NAME":0.2 "$CMD3" C-m

# Foco no terminal livre (pane 3)
tmux select-pane -t "$SESSION_NAME":0.3

tmux set -g status on
tmux set -g status-interval 5
tmux set -g status-left "#[bg=blue]#[fg=yellow] #[bold]$SESSION_NAME :: #[default]"
tmux set -g status-right "#[fg=white]#[bg=red]  #[bold] Opt+Q [quit] | Opt+R [reload] "
tmux bind-key -n M-q confirm-before -p "Tem certeza que deseja fechar o monitor?" "kill-session"
tmux bind-key -n M-r run-shell "~/.tmux/scripts/reload_monitoring.sh '$WORKDIR'"

tmux attach-session -t "$SESSION_NAME"

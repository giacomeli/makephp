# Alias úteis para dev
alias artisan='php artisan'
alias tinker='php artisan tinker'

alias cls='clear'
alias ll='ls -lah --color=auto'
alias l='ls -l'
alias la='ls -A'
alias ..='cd ..'
alias ...='cd ../..'

# Alias para diagnóstico e rede
alias psg='ps aux | grep -i'
alias ports='netstat -tuln'
alias dfh='df -h'
alias disk='ncdu /'
alias myip='ip addr | grep inet'

alias tmonitor='/root/.tmux/scripts/monitoring.sh "$PWD"'
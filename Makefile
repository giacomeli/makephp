# makephp — ambiente Docker para PHP orquestrado por Makefile.
# O .env e carregado quando existe; make init cria a partir do .env.example.
-include .env
export $(shell [ -f .env ] && sed 's/=.*//' .env)

# Variaveis globais compartilhadas pelos modulos
SED_INPLACE=$(shell [ "$$(uname)" = "Darwin" ] && echo "sed -i ''" || echo "sed -i")
PHP_IMAGE = $(PHP_CONTAINER_NAME):$(PHP_IMAGE_TAG)

.DEFAULT_GOAL := help

help:
	@echo ""
	@echo "makephp — comandos disponiveis"
	@echo ""
	@echo "Onboarding:"
	@echo "  make init                        Cria .env, rede Docker, pastas de log e compose.apps.yml"
	@echo "  make build                       Builda a imagem PHP base dev (NO_CACHE=1 para ignorar cache)"
	@echo "  make build-prod                  Builda a imagem PHP de producao (enxuta)"
	@echo ""
	@echo "Ciclo de vida:"
	@echo "  make up                          Sobe a infraestrutura core (mongodb fica de fora)"
	@echo "  make up <servico>                Sobe um servico/app especifico (ex.: make up mongodb)"
	@echo "  make down                        Para os containers (vhosts preservados)"
	@echo "  make restart                     Reinicia todos os containers"
	@echo "  make reload-<app>                Reinicia um container especifico"
	@echo "  make logs | make ps              Logs / estado dos containers"
	@echo ""
	@echo "Apps:"
	@echo "  make register-app <app>          Gera o servico do app no compose.apps.yml a partir do .env"
	@echo "  make unregister-app <app>        Remove o servico do compose.apps.yml"
	@echo "  make build-app <app>             Builda o app, gera o vhost e recarrega o nginx"
	@echo "  make shell-<container>           Shell zsh dentro do container"
	@echo "  make artisan-<container>         php artisan"
	@echo "  make composer-<container>        composer"
	@echo "  make queue-<container>           php artisan queue:work"
	@echo ""
	@echo "Nginx:"
	@echo "  make nginx-list                  Lista os vhosts configurados"
	@echo "  make nginx-templates             Lista os templates disponiveis"
	@echo "  make nginx-conf template=<tpl> name=<site> [domain=] [root=] [php_upstream=]"
	@echo "  make nginx-html-conf name=<site> [domain=] [root=]"
	@echo "  make wordpress-conf name=<site> [domain=] [root=]"
	@echo "  make clean-confs                 Remove apenas vhosts gerados (sentinela makephp)"
	@echo ""
	@echo "SSL:"
	@echo "  make cert-gen domain=<dominio>   Emite certificado Let's Encrypt (webroot)"
	@echo "  make cert-gen-www domain=<d>     Emite para o dominio + www"
	@echo "  make enable-ssl name=<site>      Migra o vhost para o template HTTPS"
	@echo "  make cert-renew                  Renova certificados e recarrega o nginx"
	@echo ""
	@echo "DNS local:"
	@echo "  sudo make hosts-add-<app>        Adiciona os aliases do app ao /etc/hosts"
	@echo "  sudo make hosts-remove-<app>     Remove os aliases"
	@echo ""
	@echo "Validacao e publicacao:"
	@echo "  make smoke                       Teste de fumaca completo (usa examples/demo-app)"
	@echo "  make push-php                    Publica giacomeli/makephp (multi-arch) no DockerHub"
	@echo ""
	@echo "Limpeza:"
	@echo "  make clean-images | clean-cache | clean-all"
	@echo ""

# Modulos
include makefiles/php.mk
include makefiles/nginx.mk
include makefiles/apps.mk
include makefiles/system.mk

# Regra vazia para o include opcional: sem ela, o catch-all dispara quando
# o .env ainda nao existe (make tenta "reconstruir" arquivos incluidos).
.env:
	@:

# Catch-all: absorve argumentos posicionais (make build-app <app>, make up <servico>).
# Quando um unico alvo desconhecido e chamado, avisa em vez de falhar em silencio.
%:
	@if [ "$(words $(MAKECMDGOALS))" = "1" ]; then \
		echo "Alvo desconhecido: '$@'. Veja: make help"; \
	fi

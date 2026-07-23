# makephp — Makefile-driven Docker environment for PHP.
# .env is loaded when present; make init creates it from .env.example.
-include .env
export $(shell [ -f .env ] && sed 's/=.*//' .env)

# Global variables shared by the modules
SED_INPLACE=$(shell [ "$$(uname)" = "Darwin" ] && echo "sed -i ''" || echo "sed -i")
PHP_IMAGE = $(PHP_CONTAINER_NAME):$(PHP_IMAGE_TAG)

.DEFAULT_GOAL := help

help:
	@echo ""
	@echo "makephp — available commands"
	@echo ""
	@echo "Onboarding:"
	@echo "  make init                        Create .env, Docker network, log dirs and compose.apps.yml"
	@echo "  make build                       Build the dev PHP base image (NO_CACHE=1 to skip cache)"
	@echo "  make build-prod                  Build the slim production PHP image"
	@echo ""
	@echo "Lifecycle:"
	@echo "  make up                          Start core infrastructure (mongodb stays out)"
	@echo "  make up <service>                Start a specific service/app (e.g. make up mongodb)"
	@echo "  make down                        Stop containers (vhosts are preserved)"
	@echo "  make restart                     Restart all containers"
	@echo "  make reload-<app>                Restart a single container"
	@echo "  make logs | make ps              Logs / container status"
	@echo ""
	@echo "Apps:"
	@echo "  make register-app <app>          Generate the app service in compose.apps.yml from .env"
	@echo "  make unregister-app <app>        Remove the app service from compose.apps.yml"
	@echo "  make build-app <app>             Build the app, generate its vhost and reload nginx"
	@echo "  make shell-<container>           zsh shell inside the container"
	@echo "  make artisan-<container>         php artisan"
	@echo "  make composer-<container>        composer"
	@echo "  make queue-<container>           php artisan queue:work"
	@echo ""
	@echo "Nginx:"
	@echo "  make nginx-list                  List configured vhosts"
	@echo "  make nginx-templates             List available templates"
	@echo "  make nginx-conf template=<tpl> name=<site> [domain=] [root=] [php_upstream=] [port=]"
	@echo "  make nginx-html-conf name=<site> [domain=] [root=]"
	@echo "  make wordpress-conf name=<site> [domain=] [root=]"
	@echo "  make clean-confs                 Remove only generated vhosts (makephp sentinel)"
	@echo ""
	@echo "SSL:"
	@echo "  make cert-gen domain=<domain>    Issue a Let's Encrypt certificate (webroot)"
	@echo "  make cert-gen-www domain=<d>     Issue for the domain + www"
	@echo "  make enable-ssl name=<site>      Switch a vhost to the HTTPS template"
	@echo "  make cert-renew                  Renew certificates and reload nginx"
	@echo ""
	@echo "Local DNS:"
	@echo "  sudo make hosts-add-<app>        Add the app aliases to /etc/hosts"
	@echo "  sudo make hosts-remove-<app>     Remove the aliases"
	@echo ""
	@echo "Validation and publishing:"
	@echo "  make smoke                       Full smoke test (uses examples/demo-app)"
	@echo "  make push-php                    Publish giacomeli/makephp (multi-arch) to DockerHub"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean-images | clean-cache | clean-all"
	@echo ""

# Modules
include makefiles/php.mk
include makefiles/nginx.mk
include makefiles/apps.mk
include makefiles/system.mk

# Empty rule for the optional include: without it, the catch-all fires when
# .env does not exist yet (make tries to "rebuild" included files).
.env:
	@:

# Catch-all: absorbs positional arguments (make build-app <app>, make up <service>).
# When a single unknown target is invoked, warn instead of failing silently.
%:
	@if [ "$(words $(MAKECMDGOALS))" = "1" ]; then \
		echo "Unknown target: '$@'. See: make help"; \
	fi

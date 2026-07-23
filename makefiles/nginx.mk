# === App Management ===
build-app:
	@APP=$(word 2, $(MAKECMDGOALS)); \
	if [ -z "$$APP" ]; then \
		echo "Erro: informe o nome do app. Exemplo: make build-app demo-app"; exit 1; \
	fi; \
	$(MAKE) build-app-$$APP; exit 0

build-app-%:
	@APP=$*; \
	echo "Building app $$APP..."; \
	docker compose build $$APP; \
	$(MAKE) generate-nginx-conf-$$APP; \
	MODE=$$(grep -m1 "$$(echo $$APP | tr 'a-z-' 'A-Z_')_NGINX_MODE=" .env | cut -d= -f2 | tr -d '"'); \
	if [ "$$MODE" != "none" ] && [ -n "$$MODE" ]; then \
		$(MAKE) nginx-reload-safe; \
	fi

##### nginx.mk - geracao de confs do Nginx #####

.PHONY: nginx-templates nginx-list nginx-conf nginx-html-conf generate-nginx-conf-% wordpress-conf enable-ssl cert-gen cert-gen-www cert-renew nginx-reload-safe

TEMPLATES_DIR ?= nginx/templates
NGINX_CONF_DIR ?= nginx/conf.d
NGINX_SENTINEL := \# generated-by: makephp

CERTBOT_EMAIL ?= $(shell grep -m1 '^CERTBOT_EMAIL=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')
CERTBOT_STAGING ?= 0

# Valida a config dentro do container (se estiver rodando) e recarrega o nginx.
# Em conf invalida: aborta SEM derrubar o nginx que esta no ar.
nginx-reload-safe:
	@if docker compose ps --status running nginx 2>/dev/null | grep -q nginx; then \
		if docker compose exec -T nginx nginx -t >/dev/null 2>&1; then \
			docker compose exec -T nginx nginx -s reload >/dev/null 2>&1 || docker compose restart nginx; \
			echo "Nginx validado (nginx -t) e recarregado."; \
		else \
			echo "ERRO: nginx -t reprovou a configuracao gerada:"; \
			docker compose exec -T nginx nginx -t 2>&1 | sed 's/^/  /'; \
			echo "O nginx NAO foi recarregado. Corrija ou remova o conf recem-gerado em $(NGINX_CONF_DIR)/."; \
			exit 1; \
		fi; \
	else \
		echo "Aviso: container nginx nao esta rodando; validacao adiada para o proximo make up."; \
	fi

nginx-templates:
	@echo "Templates disponiveis em $(TEMPLATES_DIR):"
	@ls -1 $(TEMPLATES_DIR) 2>/dev/null | sed 's/^/  - /' || echo "  (vazio)"

nginx-list:
	@echo ""; \
	echo "Sites configurados em $(NGINX_CONF_DIR):"; \
	echo ""; \
	if [ ! -d "$(NGINX_CONF_DIR)" ] || [ -z "$$(ls -A $(NGINX_CONF_DIR)/*.conf 2>/dev/null)" ]; then \
		echo "  Nenhum site configurado."; echo ""; exit 0; \
	fi; \
	printf "%-22s %-34s %-8s %-10s %s\n" "SITE" "DOMINIO" "PORTA" "SSL" "ROOT"; \
	printf "%-22s %-34s %-8s %-10s %s\n" "----" "-------" "-----" "---" "----"; \
	for conf in $(NGINX_CONF_DIR)/*.conf; do \
		[ -f "$$conf" ] || continue; \
		SITE_NAME=$$(basename "$$conf" .conf); \
		DOMAIN=$$(grep "^[ \t]*server_name " "$$conf" | head -1 | awk '{gsub(/;$$/, ""); print $$2}'); \
		ROOT=$$(grep "^[ \t]*root " "$$conf" | grep -v certbot | head -1 | awk '{gsub(/;$$/, ""); print $$2}'); \
		if grep -q "listen 443 ssl" "$$conf" 2>/dev/null; then SSL="https"; \
		elif grep -q "ssl_certificate" "$$conf" 2>/dev/null; then SSL="parcial"; \
		else SSL="http"; fi; \
		PORT=$$(grep "^[ \t]*listen " "$$conf" | grep -v 443 | head -1 | awk '{print $$2}' | sed 's/;//'); \
		printf "%-22s %-34s %-8s %-10s %s\n" "$$SITE_NAME" "$$DOMAIN" "$${PORT:-80}" "$$SSL" "$$ROOT"; \
	done; \
	echo ""; \
	TOTAL=$$(ls -1 $(NGINX_CONF_DIR)/*.conf 2>/dev/null | wc -l | xargs); \
	SSL_COUNT=$$(grep -l "listen 443 ssl" $(NGINX_CONF_DIR)/*.conf 2>/dev/null | wc -l | xargs); \
	echo "Total: $$TOTAL site(s) | $$SSL_COUNT com SSL/HTTPS"; \
	echo ""

nginx-conf:
	@if [ -z "$(template)" ]; then \
		echo "Erro: informe template= (ex.: template=html, template=proxy)"; exit 2; \
	fi; \
	if [ -z "$(name)" ]; then \
		echo "Erro: informe name= (ex.: name=meusite)"; exit 2; \
	fi; \
	mkdir -p "$(NGINX_CONF_DIR)"; \
	TP1="$(TEMPLATES_DIR)/$(template)"; \
	TP2="$(TEMPLATES_DIR)/nginx-model-$(template).conf"; \
	TP3="$(TEMPLATES_DIR)/$(template).conf"; \
	if   [ -f "$$TP1" ]; then TEMPLATE_PATH="$$TP1"; \
	elif [ -f "$$TP2" ]; then TEMPLATE_PATH="$$TP2"; \
	elif [ -f "$$TP3" ]; then TEMPLATE_PATH="$$TP3"; \
	else \
		echo "Erro: template nao encontrado: '$(template)'. Veja 'make nginx-templates'."; exit 3; \
	fi; \
	OUT="$(NGINX_CONF_DIR)/$(name).conf"; \
	cp "$$TEMPLATE_PATH" "$$OUT"; \
	DOMAIN="$(domain)";  if [ -z "$$DOMAIN" ]; then DOMAIN="$(name).local"; fi; \
	ROOT_DIR="$(root)"; if [ -z "$$ROOT_DIR" ]; then ROOT_DIR="/var/www/$(name)"; fi; \
	UPSTREAM="$(php_upstream)"; if [ -z "$$UPSTREAM" ]; then UPSTREAM="php-fpm:9000"; fi; \
	APP_PORT="$(port)"; if [ -z "$$APP_PORT" ]; then APP_PORT="8000"; fi; \
	$(SED_INPLACE) "s/__SERVER_NAME__/$$DOMAIN/g" "$$OUT"; \
	$(SED_INPLACE) "s#__ROOT_PATH__#$$ROOT_DIR#g" "$$OUT"; \
	$(SED_INPLACE) "s/__APP_NAME__/$(name)/g" "$$OUT"; \
	$(SED_INPLACE) "s#__PHP_UPSTREAM__#$$UPSTREAM#g" "$$OUT"; \
	$(SED_INPLACE) "s/__APP_PORT__/$$APP_PORT/g" "$$OUT"; \
	if grep -q '__[A-Z_]*__' "$$OUT"; then \
		echo "Erro: placeholders nao resolvidos em $$OUT:"; \
		grep -o '__[A-Z_]*__' "$$OUT" | sort -u | sed 's/^/  /'; \
		rm -f "$$OUT"; exit 1; \
	fi; \
	echo "Gerado: $$OUT a partir de $$TEMPLATE_PATH"

nginx-html-conf:
	@$(MAKE) nginx-conf template=html name="$(name)" domain="$(domain)" root="$(root)"

generate-nginx-conf-%:
	@APP=$*; \
	VAR_NAME=$$(echo $$APP | tr 'a-z-' 'A-Z_'); \
	ALIASES=$$(grep "$${VAR_NAME}_ALIASES=" .env | cut -d= -f2- | sed 's/^"//; s/"$$//' | tr '\n' ' '); \
	PORT=$$(grep "$${VAR_NAME}_PORT=" .env | cut -d= -f2 | tr -d '"'); \
	MODE=$$(grep -m1 "$${VAR_NAME}_NGINX_MODE=" .env | cut -d= -f2 | tr -d '"'); \
	MODE=$${MODE:-none}; \
	if [ "$$MODE" = "none" ]; then \
		echo "Modo 'none' para $$APP: nenhum vhost gerado."; exit 0; \
	fi; \
	TP1="$(TEMPLATES_DIR)/$$MODE"; \
	TP2="$(TEMPLATES_DIR)/nginx-model-$$MODE.conf"; \
	TP3="$(TEMPLATES_DIR)/$$MODE.conf"; \
	if   [ -f "$$TP1" ]; then TEMPLATE_PATH="$$TP1"; \
	elif [ -f "$$TP2" ]; then TEMPLATE_PATH="$$TP2"; \
	elif [ -f "$$TP3" ]; then TEMPLATE_PATH="$$TP3"; \
	else \
		echo "Erro: template nao encontrado para o modo '$$MODE' em $(TEMPLATES_DIR)"; exit 1; \
	fi; \
	DPP=$$(grep -m1 '^DOCKER_PROJECT_PATH=' .env | cut -d= -f2 | tr -d '"'); \
	DPP=$${DPP:-/var/www}; \
	ROOT_PATH=$$(grep -m1 "$${VAR_NAME}_NGINX_ROOT=" .env | cut -d= -f2 | tr -d '"'); \
	if [ -z "$$ROOT_PATH" ]; then \
		case "$$MODE" in \
			php|wordpress*) ROOT_PATH="$$DPP/$$APP/public" ;; \
			*) ROOT_PATH="$$DPP/$$APP" ;; \
		esac; \
	fi; \
	UPSTREAM=$$(grep -m1 "$${VAR_NAME}_PHP_UPSTREAM=" .env | cut -d= -f2 | tr -d '"'); \
	UPSTREAM=$${UPSTREAM:-php-fpm:9000}; \
	mkdir -p "$(NGINX_CONF_DIR)"; \
	APP_CONF="$(NGINX_CONF_DIR)/$$APP.conf"; \
	cp "$$TEMPLATE_PATH" "$$APP_CONF"; \
	$(SED_INPLACE) "s|__SERVER_NAME__|$$ALIASES|g" "$$APP_CONF"; \
	$(SED_INPLACE) "s|__APP_NAME__|$$APP|g" "$$APP_CONF"; \
	$(SED_INPLACE) "s|__APP_PORT__|$$PORT|g" "$$APP_CONF"; \
	$(SED_INPLACE) "s|__ROOT_PATH__|$$ROOT_PATH|g" "$$APP_CONF"; \
	$(SED_INPLACE) "s|__PHP_UPSTREAM__|$$UPSTREAM|g" "$$APP_CONF"; \
	if grep -q '__[A-Z_]*__' "$$APP_CONF"; then \
		echo "Erro: placeholders nao resolvidos em $$APP_CONF:"; \
		grep -o '__[A-Z_]*__' "$$APP_CONF" | sort -u | sed 's/^/  /'; \
		rm -f "$$APP_CONF"; exit 1; \
	fi; \
	echo "Gerado: $$APP_CONF a partir de $$TEMPLATE_PATH (root: $$ROOT_PATH)"

wordpress-conf:
	@if [ -z "$(name)" ]; then \
		echo "Erro: a variavel 'name' e obrigatoria."; \
		exit 1; \
	fi; \
	VAR_NAME=$$(echo $(name) | tr 'a-z-' 'A-Z_'); \
	ALIASES_FROM_ENV=$$(grep "$${VAR_NAME}_ALIASES=" .env 2>/dev/null | cut -d= -f2- | sed 's/^"//; s/"$$//' | tr '\n' ' '); \
	PROJECT_PATH_FROM_ENV=$$(grep "$${VAR_NAME}_PROJECT_PATH=" .env 2>/dev/null | cut -d= -f2 | tr -d '"'); \
	DOMAIN="$(domain)"; \
	if [ -z "$$DOMAIN" ]; then \
		if [ -n "$$ALIASES_FROM_ENV" ]; then DOMAIN="$$ALIASES_FROM_ENV"; else DOMAIN="$(name).local"; fi; \
	fi; \
	ROOT_PATH="$(root)"; \
	if [ -z "$$ROOT_PATH" ]; then \
		if [ -n "$$PROJECT_PATH_FROM_ENV" ]; then \
			ROOT_PATH="/var/www/$$(basename "$$PROJECT_PATH_FROM_ENV")"; \
		else \
			ROOT_PATH="/var/www/$(name)"; \
		fi; \
	fi; \
	UPSTREAM="$(php_upstream)"; if [ -z "$$UPSTREAM" ]; then UPSTREAM="php-fpm:9000"; fi; \
	MODEL="$(TEMPLATES_DIR)/nginx-model-wordpress-http.conf"; \
	APP_CONF="$(NGINX_CONF_DIR)/$(name).conf"; \
	if [ ! -f "$$MODEL" ]; then echo "Erro: template HTTP nao encontrado: $$MODEL"; exit 1; fi; \
	echo "Gerando config WordPress para $(name) (dominio: $$DOMAIN, root: $$ROOT_PATH)"; \
	mkdir -p "$(NGINX_CONF_DIR)"; \
	cp "$$MODEL" "$$APP_CONF"; \
	$(SED_INPLACE) -e "s|__SERVER_NAME__|$$DOMAIN|g" -e "s|__APP_NAME__|$(name)|g" -e "s#__ROOT_PATH__#$$ROOT_PATH#g" -e "s#__PHP_UPSTREAM__#$$UPSTREAM#g" "$$APP_CONF"; \
	echo "Gerado: $$APP_CONF"; \
	$(MAKE) nginx-reload-safe

enable-ssl:
	@if [ -z "$(name)" ]; then \
		echo "Erro: a variavel 'name' e obrigatoria."; \
		exit 1; \
	fi; \
	APP_CONF="$(NGINX_CONF_DIR)/$(name).conf"; \
	if [ ! -f "$$APP_CONF" ]; then \
		echo "Erro: $$APP_CONF nao existe. Gere antes com 'make nginx-conf' ou 'make build-app'."; \
		exit 1; \
	fi; \
	CURRENT_ROOT=$$(grep "^[ \t]*root " "$$APP_CONF" | grep -v certbot | head -1 | awk '{gsub(/;$$/, ""); for(i=2; i<=NF; i++) printf "%s%s", $$i, (i<NF ? " " : "")}'); \
	CURRENT_DOMAIN=$$(grep "^[ \t]*server_name " "$$APP_CONF" | head -1 | awk '{gsub(/;$$/, ""); for(i=2; i<=NF; i++) printf "%s%s", $$i, (i<NF ? " " : "")}'); \
	CURRENT_UPSTREAM=$$(grep "fastcgi_pass" "$$APP_CONF" | head -1 | awk '{gsub(/;$$/, ""); print $$2}'); \
	if [ -z "$$CURRENT_UPSTREAM" ]; then CURRENT_UPSTREAM="php-fpm:9000"; fi; \
	ROOT_PATH="$(root)"; if [ -z "$$ROOT_PATH" ]; then ROOT_PATH="$$CURRENT_ROOT"; fi; \
	DOMAIN="$(domain)"; if [ -z "$$DOMAIN" ]; then DOMAIN="$$CURRENT_DOMAIN"; fi; \
	CERT_DOMAIN="$(cert_domain)"; if [ -z "$$CERT_DOMAIN" ]; then CERT_DOMAIN=$$(echo $$DOMAIN | awk '{print $$1}'); fi; \
	PHP_UPSTREAM="$(php_upstream)"; if [ -z "$$PHP_UPSTREAM" ]; then PHP_UPSTREAM="$$CURRENT_UPSTREAM"; fi; \
	TEMPLATE="$(template)"; \
	if [ -z "$$TEMPLATE" ]; then \
		if grep -q "fastcgi_pass" "$$APP_CONF"; then \
			TEMPLATE="$(TEMPLATES_DIR)/nginx-model-php-https.conf"; \
		else \
			TEMPLATE="$(TEMPLATES_DIR)/nginx-model-wordpress-https.conf"; \
		fi; \
	else \
		if [ -f "$(TEMPLATES_DIR)/$$TEMPLATE" ]; then TEMPLATE="$(TEMPLATES_DIR)/$$TEMPLATE"; \
		elif [ -f "$(TEMPLATES_DIR)/nginx-model-$$TEMPLATE.conf" ]; then TEMPLATE="$(TEMPLATES_DIR)/nginx-model-$$TEMPLATE.conf"; \
		elif [ -f "$(TEMPLATES_DIR)/$$TEMPLATE.conf" ]; then TEMPLATE="$(TEMPLATES_DIR)/$$TEMPLATE.conf"; \
		else echo "Erro: template nao encontrado: $$TEMPLATE"; exit 1; fi; \
	fi; \
	if [ ! -f "$$TEMPLATE" ]; then echo "Erro: template HTTPS nao encontrado: $$TEMPLATE"; exit 1; fi; \
	echo "Habilitando SSL para $(name) (dominio: $$DOMAIN, cert: $$CERT_DOMAIN, template: $$TEMPLATE)"; \
	mkdir -p "$(NGINX_CONF_DIR)"; \
	cp "$$TEMPLATE" "$$APP_CONF"; \
	$(SED_INPLACE) "s|__SERVER_NAME__|$$DOMAIN|g" "$$APP_CONF"; \
	$(SED_INPLACE) "s|__CERT_DOMAIN__|$$CERT_DOMAIN|g" "$$APP_CONF"; \
	$(SED_INPLACE) "s|__APP_NAME__|$(name)|g" "$$APP_CONF"; \
	$(SED_INPLACE) "s#__ROOT_PATH__#$$ROOT_PATH#g" "$$APP_CONF"; \
	if grep -q "__PHP_UPSTREAM__" "$$APP_CONF"; then \
		$(SED_INPLACE) "s#__PHP_UPSTREAM__#$$PHP_UPSTREAM#g" "$$APP_CONF"; \
	fi; \
	echo "Configuracao SSL gravada em $$APP_CONF"; \
	$(MAKE) nginx-reload-safe

cert-gen:
	@if [ -z "$(CERTBOT_EMAIL)" ]; then \
		echo "Erro: CERTBOT_EMAIL nao definido no ambiente ou .env"; exit 2; \
	fi; \
	if [ -z "$(domain)$(domains)" ]; then \
		echo "Erro: informe domain=<dominio> ou domains=\"dominio1 dominio2\""; exit 2; \
	fi; \
	if ! docker compose config --services | grep -q '^certbot$$'; then \
		echo "Erro: servico 'certbot' nao encontrado no docker compose"; exit 1; \
	fi; \
	DOMS="$(domain) $(domains)"; \
	DOMS=$$(echo $$DOMS | tr ',' ' '); \
	FLAGS=""; \
	for D in $$DOMS; do FLAGS="$$FLAGS -d $$D"; done; \
	STAGING_FLAG=""; [ "$(CERTBOT_STAGING)" = "1" ] && STAGING_FLAG="--staging"; \
	echo "Solicitando certificado para: $$DOMS"; \
	docker compose run --rm --no-deps certbot certonly --webroot --webroot-path /var/www/certbot $$FLAGS --email "$(CERTBOT_EMAIL)" --agree-tos --no-eff-email $$STAGING_FLAG; \
	echo "Certificado emitido/atualizado."

cert-gen-www:
	@if [ -z "$(domain)" ]; then echo "Erro: use make cert-gen-www domain=exemplo.com.br"; exit 2; fi; \
	$(MAKE) cert-gen domains="$(domain) www.$(domain)"

cert-renew:
	@if ! docker compose config --services | grep -q '^certbot$$'; then \
		echo "Erro: servico 'certbot' nao encontrado no docker compose"; exit 1; \
	fi; \
	STAGING_FLAG=""; [ "$(CERTBOT_STAGING)" = "1" ] && STAGING_FLAG="--staging"; \
	echo "Renovando certificados..."; \
	docker compose run --rm --no-deps certbot renew $$STAGING_FLAG || true; \
	if docker compose ps --status running nginx 2>/dev/null | grep -q nginx; then \
		docker compose exec -T nginx nginx -s reload && echo "Nginx recarregado com os certificados novos."; \
	fi; \
	echo "Renovacao executada."

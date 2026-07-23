# === App management ===
build-app:
	@APP=$(word 2, $(MAKECMDGOALS)); \
	if [ -z "$$APP" ]; then \
		echo "Error: provide the app name. Example: make build-app demo-app"; exit 1; \
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

##### nginx.mk - nginx vhost generation #####

.PHONY: nginx-templates nginx-list nginx-conf nginx-html-conf generate-nginx-conf-% wordpress-conf enable-ssl cert-gen cert-gen-www cert-renew nginx-reload-safe

TEMPLATES_DIR ?= nginx/templates
NGINX_CONF_DIR ?= nginx/conf.d
NGINX_SENTINEL := \# generated-by: makephp

CERTBOT_EMAIL ?= $(shell grep -m1 '^CERTBOT_EMAIL=' .env 2>/dev/null | cut -d= -f2 | tr -d '"')
CERTBOT_STAGING ?= 0

# Validates the configuration inside the container (when running) and reloads
# nginx. On invalid config: aborts WITHOUT taking down the running nginx.
nginx-reload-safe:
	@if docker compose ps --status running nginx 2>/dev/null | grep -q nginx; then \
		if docker compose exec -T nginx nginx -t >/dev/null 2>&1; then \
			docker compose exec -T nginx nginx -s reload >/dev/null 2>&1 || docker compose restart nginx; \
			echo "Nginx validated (nginx -t) and reloaded."; \
		else \
			echo "ERROR: nginx -t rejected the generated configuration:"; \
			docker compose exec -T nginx nginx -t 2>&1 | sed 's/^/  /'; \
			echo "Nginx was NOT reloaded. Fix or remove the newly generated conf in $(NGINX_CONF_DIR)/."; \
			exit 1; \
		fi; \
	else \
		echo "Warning: nginx container is not running; validation deferred to the next make up."; \
	fi

nginx-templates:
	@echo "Templates available in $(TEMPLATES_DIR):"
	@ls -1 $(TEMPLATES_DIR) 2>/dev/null | sed 's/^/  - /' || echo "  (empty)"

nginx-list:
	@echo ""; \
	echo "Sites configured in $(NGINX_CONF_DIR):"; \
	echo ""; \
	if [ ! -d "$(NGINX_CONF_DIR)" ] || [ -z "$$(ls -A $(NGINX_CONF_DIR)/*.conf 2>/dev/null)" ]; then \
		echo "  No sites configured."; echo ""; exit 0; \
	fi; \
	printf "%-22s %-34s %-8s %-10s %s\n" "SITE" "DOMAIN" "PORT" "SSL" "ROOT"; \
	printf "%-22s %-34s %-8s %-10s %s\n" "----" "------" "----" "---" "----"; \
	for conf in $(NGINX_CONF_DIR)/*.conf; do \
		[ -f "$$conf" ] || continue; \
		SITE_NAME=$$(basename "$$conf" .conf); \
		DOMAIN=$$(grep "^[ \t]*server_name " "$$conf" | head -1 | awk '{gsub(/;$$/, ""); print $$2}'); \
		ROOT=$$(grep "^[ \t]*root " "$$conf" | grep -v certbot | head -1 | awk '{gsub(/;$$/, ""); print $$2}'); \
		if grep -q "listen 443 ssl" "$$conf" 2>/dev/null; then SSL="https"; \
		elif grep -q "ssl_certificate" "$$conf" 2>/dev/null; then SSL="partial"; \
		else SSL="http"; fi; \
		PORT=$$(grep "^[ \t]*listen " "$$conf" | grep -v 443 | head -1 | awk '{print $$2}' | sed 's/;//'); \
		printf "%-22s %-34s %-8s %-10s %s\n" "$$SITE_NAME" "$$DOMAIN" "$${PORT:-80}" "$$SSL" "$$ROOT"; \
	done; \
	echo ""; \
	TOTAL=$$(ls -1 $(NGINX_CONF_DIR)/*.conf 2>/dev/null | wc -l | xargs); \
	SSL_COUNT=$$(grep -l "listen 443 ssl" $(NGINX_CONF_DIR)/*.conf 2>/dev/null | wc -l | xargs); \
	echo "Total: $$TOTAL site(s) | $$SSL_COUNT with SSL/HTTPS"; \
	echo ""

nginx-conf:
	@if [ -z "$(template)" ]; then \
		echo "Error: provide template= (e.g. template=html, template=proxy)"; exit 2; \
	fi; \
	if [ -z "$(name)" ]; then \
		echo "Error: provide name= (e.g. name=mysite)"; exit 2; \
	fi; \
	mkdir -p "$(NGINX_CONF_DIR)"; \
	TP1="$(TEMPLATES_DIR)/$(template)"; \
	TP2="$(TEMPLATES_DIR)/nginx-model-$(template).conf"; \
	TP3="$(TEMPLATES_DIR)/$(template).conf"; \
	if   [ -f "$$TP1" ]; then TEMPLATE_PATH="$$TP1"; \
	elif [ -f "$$TP2" ]; then TEMPLATE_PATH="$$TP2"; \
	elif [ -f "$$TP3" ]; then TEMPLATE_PATH="$$TP3"; \
	else \
		echo "Error: template not found: '$(template)'. See 'make nginx-templates'."; exit 3; \
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
		echo "Error: unresolved placeholders in $$OUT:"; \
		grep -o '__[A-Z_]*__' "$$OUT" | sort -u | sed 's/^/  /'; \
		rm -f "$$OUT"; exit 1; \
	fi; \
	echo "Generated: $$OUT from $$TEMPLATE_PATH"

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
		echo "Mode 'none' for $$APP: no vhost generated."; exit 0; \
	fi; \
	TP1="$(TEMPLATES_DIR)/$$MODE"; \
	TP2="$(TEMPLATES_DIR)/nginx-model-$$MODE.conf"; \
	TP3="$(TEMPLATES_DIR)/$$MODE.conf"; \
	if   [ -f "$$TP1" ]; then TEMPLATE_PATH="$$TP1"; \
	elif [ -f "$$TP2" ]; then TEMPLATE_PATH="$$TP2"; \
	elif [ -f "$$TP3" ]; then TEMPLATE_PATH="$$TP3"; \
	else \
		echo "Error: no template found for mode '$$MODE' in $(TEMPLATES_DIR)"; exit 1; \
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
		echo "Error: unresolved placeholders in $$APP_CONF:"; \
		grep -o '__[A-Z_]*__' "$$APP_CONF" | sort -u | sed 's/^/  /'; \
		rm -f "$$APP_CONF"; exit 1; \
	fi; \
	echo "Generated: $$APP_CONF from $$TEMPLATE_PATH (root: $$ROOT_PATH)"

wordpress-conf:
	@if [ -z "$(name)" ]; then \
		echo "Error: the 'name' variable is required."; \
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
	if [ ! -f "$$MODEL" ]; then echo "Error: HTTP template not found: $$MODEL"; exit 1; fi; \
	echo "Generating WordPress config for $(name) (domain: $$DOMAIN, root: $$ROOT_PATH)"; \
	mkdir -p "$(NGINX_CONF_DIR)"; \
	cp "$$MODEL" "$$APP_CONF"; \
	$(SED_INPLACE) -e "s|__SERVER_NAME__|$$DOMAIN|g" -e "s|__APP_NAME__|$(name)|g" -e "s#__ROOT_PATH__#$$ROOT_PATH#g" -e "s#__PHP_UPSTREAM__#$$UPSTREAM#g" "$$APP_CONF"; \
	echo "Generated: $$APP_CONF"; \
	$(MAKE) nginx-reload-safe

enable-ssl:
	@if [ -z "$(name)" ]; then \
		echo "Error: the 'name' variable is required."; \
		exit 1; \
	fi; \
	APP_CONF="$(NGINX_CONF_DIR)/$(name).conf"; \
	if [ ! -f "$$APP_CONF" ]; then \
		echo "Error: $$APP_CONF does not exist. Generate it first with 'make nginx-conf' or 'make build-app'."; \
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
		else echo "Error: template not found: $$TEMPLATE"; exit 1; fi; \
	fi; \
	if [ ! -f "$$TEMPLATE" ]; then echo "Error: HTTPS template not found: $$TEMPLATE"; exit 1; fi; \
	echo "Enabling SSL for $(name) (domain: $$DOMAIN, cert: $$CERT_DOMAIN, template: $$TEMPLATE)"; \
	mkdir -p "$(NGINX_CONF_DIR)"; \
	cp "$$TEMPLATE" "$$APP_CONF"; \
	$(SED_INPLACE) "s|__SERVER_NAME__|$$DOMAIN|g" "$$APP_CONF"; \
	$(SED_INPLACE) "s|__CERT_DOMAIN__|$$CERT_DOMAIN|g" "$$APP_CONF"; \
	$(SED_INPLACE) "s|__APP_NAME__|$(name)|g" "$$APP_CONF"; \
	$(SED_INPLACE) "s#__ROOT_PATH__#$$ROOT_PATH#g" "$$APP_CONF"; \
	if grep -q "__PHP_UPSTREAM__" "$$APP_CONF"; then \
		$(SED_INPLACE) "s#__PHP_UPSTREAM__#$$PHP_UPSTREAM#g" "$$APP_CONF"; \
	fi; \
	echo "SSL configuration written to $$APP_CONF"; \
	$(MAKE) nginx-reload-safe

cert-gen:
	@if [ -z "$(CERTBOT_EMAIL)" ]; then \
		echo "Error: CERTBOT_EMAIL is not set in the environment or .env"; exit 2; \
	fi; \
	if [ -z "$(domain)$(domains)" ]; then \
		echo "Error: provide domain=<domain> or domains=\"domain1 domain2\""; exit 2; \
	fi; \
	if ! docker compose config --services | grep -q '^certbot$$'; then \
		echo "Error: 'certbot' service not found in docker compose"; exit 1; \
	fi; \
	DOMS="$(domain) $(domains)"; \
	DOMS=$$(echo $$DOMS | tr ',' ' '); \
	FLAGS=""; \
	for D in $$DOMS; do FLAGS="$$FLAGS -d $$D"; done; \
	STAGING_FLAG=""; [ "$(CERTBOT_STAGING)" = "1" ] && STAGING_FLAG="--staging"; \
	echo "Requesting certificate for: $$DOMS"; \
	docker compose run --rm --no-deps certbot certonly --webroot --webroot-path /var/www/certbot $$FLAGS --email "$(CERTBOT_EMAIL)" --agree-tos --no-eff-email $$STAGING_FLAG; \
	echo "Certificate issued/updated."

cert-gen-www:
	@if [ -z "$(domain)" ]; then echo "Error: use make cert-gen-www domain=example.com"; exit 2; fi; \
	$(MAKE) cert-gen domains="$(domain) www.$(domain)"

cert-renew:
	@if ! docker compose config --services | grep -q '^certbot$$'; then \
		echo "Error: 'certbot' service not found in docker compose"; exit 1; \
	fi; \
	STAGING_FLAG=""; [ "$(CERTBOT_STAGING)" = "1" ] && STAGING_FLAG="--staging"; \
	echo "Renewing certificates..."; \
	docker compose run --rm --no-deps certbot renew $$STAGING_FLAG || true; \
	if docker compose ps --status running nginx 2>/dev/null | grep -q nginx; then \
		docker compose exec -T nginx nginx -s reload && echo "Nginx reloaded with the renewed certificates."; \
	fi; \
	echo "Renewal executed."

# === Onboarding ===
init:
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "Created .env from .env.example — review LOCAL_DIR and the passwords."; \
	else \
		echo ".env already exists (kept)."; \
	fi
	@docker network inspect phpdocker-network >/dev/null 2>&1 || \
		{ docker network create phpdocker-network >/dev/null && echo "Created phpdocker-network."; }
	@mkdir -p logs/php logs/nginx nginx/conf.d
	@if [ ! -f compose.apps.yml ]; then \
		printf '# Application services registered via make register-app (NOT versioned).\nservices: {}\n' > compose.apps.yml; \
		echo "Created compose.apps.yml (stub)."; \
	fi
	@echo "Init done. Next steps: make build && make up"

check-env:
	@if [ ! -f .env ]; then \
		echo ".env file not found. Run: make init"; exit 1; \
	fi

# === Compose ===
up: check-env
	@if [ "$(word 2, $(MAKECMDGOALS))" = "" ]; then \
		echo "Starting core services (mongodb stays out — use make up mongodb)..."; \
		docker compose up -d php-fpm nginx mariadb redis rabbitmq postgres-timescale; \
	else \
		SERVICE=$(word 2, $(MAKECMDGOALS)); \
		echo "Starting service: $$SERVICE"; \
		$(MAKE) generate-nginx-conf-$$SERVICE; \
		docker compose up -d $$SERVICE; \
	fi

up-%: ;

down:
	@docker compose down
	@echo "Containers stopped. Vhosts in nginx/conf.d/ were preserved (use make clean-confs to remove generated ones)."

clean-confs:
	@removed=0; kept=0; \
	for conf in $(NGINX_CONF_DIR)/*.conf; do \
		[ -f "$$conf" ] || continue; \
		if head -1 "$$conf" | grep -q "generated-by: makephp"; then \
			rm -f "$$conf"; echo "removed:   $$conf"; removed=$$((removed+1)); \
		else \
			echo "preserved: $$conf (no generation sentinel)"; kept=$$((kept+1)); \
		fi; \
	done; \
	echo "clean-confs: $$removed removed, $$kept preserved."

restart:
	@docker compose restart

reload:
	@echo "Error: use the suffixed form. Example: make reload-demo-app"; exit 1

reload-%:
	@docker compose restart $*

logs:
	@docker compose logs -f

ps:
	@docker compose ps

# === Local DNS ===
hosts-add:
	@echo "Error: use the suffixed form. Example: sudo make hosts-add-demo-app"; exit 1

hosts-add-%:
	@APP=$*; \
	VAR_NAME=$$(echo $$APP | tr 'a-z-' 'A-Z_'); \
	ALIASES=$$(grep "$${VAR_NAME}_ALIASES=" .env | cut -d= -f2- | sed 's/^"//; s/"$$//'); \
	if [ -z "$$ALIASES" ]; then echo "Error: no aliases found for $$APP in .env"; exit 1; fi; \
	echo "Adding to /etc/hosts: $$ALIASES"; \
	echo "127.0.0.1 $$ALIASES" | sudo tee -a /etc/hosts > /dev/null

hosts-remove:
	@echo "Error: use the suffixed form. Example: sudo make hosts-remove-demo-app"; exit 1

hosts-remove-%:
	@APP=$*; \
	VAR_NAME=$$(echo $$APP | tr 'a-z-' 'A-Z_'); \
	ALIASES=$$(grep "$${VAR_NAME}_ALIASES=" .env | cut -d'"' -f2); \
	if [ -z "$$ALIASES" ]; then echo "Error: no aliases found for $$APP in .env"; exit 1; fi; \
	for alias in $$ALIASES; do \
		sudo sed -i.hostsbak -e "/[[:space:]]$$alias[[:space:]]/d" -e "/[[:space:]]$$alias$$/d" /etc/hosts && \
		echo "Removed: $$alias"; \
	done; \
	sudo rm -f /etc/hosts.hostsbak

# === Smoke test ===
smoke: check-env
	@bash scripts/smoke.sh

# === Cleanup ===
clean-images:
	@echo "Removing the unified PHP image..."
	@-docker rmi -f $(PHP_IMAGE)
	@-docker rmi -f $(PHP_CONTAINER_NAME):dev
	@echo "Removing dangling images..."
	@-docker images --filter "dangling=true" -q | xargs -r docker rmi -f
	@echo "Image cleanup done."

clean-cache:
	@echo "Pruning build cache and orphan volumes..."
	@docker builder prune --force
	@docker volume prune --force
	@echo "Cache cleanup done."

clean-all: clean-images clean-cache
	@echo "Full cleanup done."

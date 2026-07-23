# === Onboarding ===
init:
	@if [ ! -f .env ]; then \
		cp .env.example .env; \
		echo "Criado .env a partir de .env.example — revise LOCAL_DIR e as senhas."; \
	else \
		echo ".env ja existe (mantido)."; \
	fi
	@docker network inspect phpdocker-network >/dev/null 2>&1 || \
		{ docker network create phpdocker-network >/dev/null && echo "Rede phpdocker-network criada."; }
	@mkdir -p logs/php logs/nginx nginx/conf.d
	@if [ ! -f compose.apps.yml ]; then \
		printf '# Servicos de aplicacao registrados via make register-app (arquivo NAO versionado).\nservices: {}\n' > compose.apps.yml; \
		echo "Criado compose.apps.yml (stub)."; \
	fi
	@echo "Init concluido. Proximos passos: make build && make up"

check-env:
	@if [ ! -f .env ]; then \
		echo "Arquivo .env nao encontrado. Rode: make init"; exit 1; \
	fi

# === Compose ===
up: check-env
	@if [ "$(word 2, $(MAKECMDGOALS))" = "" ]; then \
		echo "Subindo servicos core (mongodb fica de fora — use make up mongodb)..."; \
		docker compose up -d php-fpm nginx mariadb redis rabbitmq postgres-timescale; \
	else \
		SERVICE=$(word 2, $(MAKECMDGOALS)); \
		echo "Subindo servico: $$SERVICE"; \
		$(MAKE) generate-nginx-conf-$$SERVICE; \
		docker compose up -d $$SERVICE; \
	fi

up-%: ;

down:
	@docker compose down
	@echo "Containers parados. Vhosts em nginx/conf.d/ foram preservados (use make clean-confs para limpar os gerados)."

clean-confs:
	@removed=0; kept=0; \
	for conf in $(NGINX_CONF_DIR)/*.conf; do \
		[ -f "$$conf" ] || continue; \
		if head -1 "$$conf" | grep -q "generated-by: makephp"; then \
			rm -f "$$conf"; echo "removido:   $$conf"; removed=$$((removed+1)); \
		else \
			echo "preservado: $$conf (sem sentinela de geracao)"; kept=$$((kept+1)); \
		fi; \
	done; \
	echo "clean-confs: $$removed removido(s), $$kept preservado(s)."

restart:
	@docker compose restart

reload:
	@echo "Erro: informe o app com sufixo. Exemplo: make reload-demo-app"; exit 1

reload-%:
	@docker compose restart $*

logs:
	@docker compose logs -f

ps:
	@docker compose ps

# === DNS local ===
hosts-add:
	@echo "Erro: informe o app com sufixo. Exemplo: sudo make hosts-add-demo-app"; exit 1

hosts-add-%:
	@APP=$*; \
	VAR_NAME=$$(echo $$APP | tr 'a-z-' 'A-Z_'); \
	ALIASES=$$(grep "$${VAR_NAME}_ALIASES=" .env | cut -d= -f2- | sed 's/^"//; s/"$$//'); \
	if [ -z "$$ALIASES" ]; then echo "Erro: alias nao encontrado para $$APP no .env"; exit 1; fi; \
	echo "Adicionando ao /etc/hosts: $$ALIASES"; \
	echo "127.0.0.1 $$ALIASES" | sudo tee -a /etc/hosts > /dev/null

hosts-remove:
	@echo "Erro: informe o app com sufixo. Exemplo: sudo make hosts-remove-demo-app"; exit 1

hosts-remove-%:
	@APP=$*; \
	VAR_NAME=$$(echo $$APP | tr 'a-z-' 'A-Z_'); \
	ALIASES=$$(grep "$${VAR_NAME}_ALIASES=" .env | cut -d'"' -f2); \
	if [ -z "$$ALIASES" ]; then echo "Erro: alias nao encontrado para $$APP no .env"; exit 1; fi; \
	for alias in $$ALIASES; do \
		sudo sed -i.hostsbak -e "/[[:space:]]$$alias[[:space:]]/d" -e "/[[:space:]]$$alias$$/d" /etc/hosts && \
		echo "Removido: $$alias"; \
	done; \
	sudo rm -f /etc/hosts.hostsbak

# === Smoke test ===
smoke: check-env
	@bash scripts/smoke.sh

# === Limpeza ===
clean-images:
	@echo "Removendo imagem PHP unificada..."
	@-docker rmi -f $(PHP_IMAGE)
	@-docker rmi -f $(PHP_CONTAINER_NAME):dev
	@echo "Removendo imagens dangling..."
	@-docker images --filter "dangling=true" -q | xargs -r docker rmi -f
	@echo "Limpeza de imagens concluida."

clean-cache:
	@echo "Limpando cache de build e volumes orfaos..."
	@docker builder prune --force
	@docker volume prune --force
	@echo "Limpeza de cache concluida."

clean-all: clean-images clean-cache
	@echo "Limpeza completa concluida."

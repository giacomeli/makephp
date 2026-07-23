# === Registro de apps no compose.apps.yml ===
# O bloco de servico e gerado a partir das variaveis <APP>_* do .env usando
# templates/compose-app.yml (delimitado por marcadores para remocao segura).

COMPOSE_APPS_FILE ?= compose.apps.yml
COMPOSE_APP_TEMPLATE ?= templates/compose-app.yml

.PHONY: register-app unregister-app

register-app: check-env
	@APP=$(word 2, $(MAKECMDGOALS)); \
	if [ -z "$$APP" ]; then \
		echo "Erro: informe o nome do app. Exemplo: make register-app demo-app"; exit 1; \
	fi; \
	$(MAKE) register-app-$$APP; exit 0

register-app-%: check-env
	@APP=$*; \
	VAR_NAME=$$(echo $$APP | tr 'a-z-' 'A-Z_'); \
	for req in PROJECT_PATH CONTAINER_NAME DOCKER_PATH; do \
		if ! grep -q "^$${VAR_NAME}_$$req=" .env; then \
			echo "Erro: variavel $${VAR_NAME}_$$req ausente no .env — registre o bloco do app antes."; exit 1; \
		fi; \
	done; \
	if [ ! -f "$(COMPOSE_APPS_FILE)" ]; then \
		printf '# Servicos de aplicacao registrados via make register-app (arquivo NAO versionado).\nservices:\n' > "$(COMPOSE_APPS_FILE)"; \
	fi; \
	if grep -q "# app:$$APP:begin" "$(COMPOSE_APPS_FILE)"; then \
		$(MAKE) unregister-app-$$APP; \
	fi; \
	if grep -q '^services: {}$$' "$(COMPOSE_APPS_FILE)"; then \
		printf '# Servicos de aplicacao registrados via make register-app (arquivo NAO versionado).\nservices:\n' > "$(COMPOSE_APPS_FILE)"; \
	fi; \
	sed -e "s/__APP_VAR__/$$VAR_NAME/g" -e "s/__APP__/$$APP/g" "$(COMPOSE_APP_TEMPLATE)" >> "$(COMPOSE_APPS_FILE)"; \
	if docker compose config -q; then \
		echo "App $$APP registrado em $(COMPOSE_APPS_FILE)."; \
	else \
		echo "Erro: configuracao compose invalida apos o registro de $$APP (bloco mantido para inspecao)."; \
		exit 1; \
	fi

unregister-app:
	@APP=$(word 2, $(MAKECMDGOALS)); \
	if [ -z "$$APP" ]; then \
		echo "Erro: informe o nome do app. Exemplo: make unregister-app demo-app"; exit 1; \
	fi; \
	$(MAKE) unregister-app-$$APP; exit 0

unregister-app-%:
	@APP=$*; \
	if [ ! -f "$(COMPOSE_APPS_FILE)" ]; then echo "Nada a remover ($(COMPOSE_APPS_FILE) nao existe)."; exit 0; fi; \
	if ! grep -q "# app:$$APP:begin" "$(COMPOSE_APPS_FILE)"; then \
		echo "App $$APP nao esta registrado em $(COMPOSE_APPS_FILE)."; exit 0; \
	fi; \
	TMP=$$(mktemp); \
	awk -v app="$$APP" ' \
		$$0 ~ ("# app:" app ":begin") {skip=1} \
		!skip {print} \
		$$0 ~ ("# app:" app ":end") {skip=0} \
	' "$(COMPOSE_APPS_FILE)" > "$$TMP" && mv "$$TMP" "$(COMPOSE_APPS_FILE)"; \
	echo "App $$APP removido de $(COMPOSE_APPS_FILE)."

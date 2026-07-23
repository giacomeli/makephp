# === App registration in compose.apps.yml ===
# The service block is generated from the <APP>_* variables in .env using
# templates/compose-app.yml (delimited by markers for safe removal).

COMPOSE_APPS_FILE ?= compose.apps.yml
COMPOSE_APP_TEMPLATE ?= templates/compose-app.yml

.PHONY: register-app unregister-app

register-app: check-env
	@APP=$(word 2, $(MAKECMDGOALS)); \
	if [ -z "$$APP" ]; then \
		echo "Error: provide the app name. Example: make register-app demo-app"; exit 1; \
	fi; \
	$(MAKE) register-app-$$APP; exit 0

register-app-%: check-env
	@APP=$*; \
	VAR_NAME=$$(echo $$APP | tr 'a-z-' 'A-Z_'); \
	for req in PROJECT_PATH CONTAINER_NAME DOCKER_PATH; do \
		if ! grep -q "^$${VAR_NAME}_$$req=" .env; then \
			echo "Error: variable $${VAR_NAME}_$$req missing in .env — add the app block first."; exit 1; \
		fi; \
	done; \
	if [ ! -f "$(COMPOSE_APPS_FILE)" ]; then \
		printf '# Application services registered via make register-app (NOT versioned).\nservices:\n' > "$(COMPOSE_APPS_FILE)"; \
	fi; \
	if grep -q "# app:$$APP:begin" "$(COMPOSE_APPS_FILE)"; then \
		$(MAKE) unregister-app-$$APP; \
	fi; \
	if grep -q '^services: {}$$' "$(COMPOSE_APPS_FILE)"; then \
		printf '# Application services registered via make register-app (NOT versioned).\nservices:\n' > "$(COMPOSE_APPS_FILE)"; \
	fi; \
	sed -e "s/__APP_VAR__/$$VAR_NAME/g" -e "s/__APP__/$$APP/g" "$(COMPOSE_APP_TEMPLATE)" >> "$(COMPOSE_APPS_FILE)"; \
	if docker compose config -q; then \
		echo "App $$APP registered in $(COMPOSE_APPS_FILE)."; \
	else \
		echo "Error: invalid compose configuration after registering $$APP (block kept for inspection)."; \
		exit 1; \
	fi

unregister-app:
	@APP=$(word 2, $(MAKECMDGOALS)); \
	if [ -z "$$APP" ]; then \
		echo "Error: provide the app name. Example: make unregister-app demo-app"; exit 1; \
	fi; \
	$(MAKE) unregister-app-$$APP; exit 0

unregister-app-%:
	@APP=$*; \
	if [ ! -f "$(COMPOSE_APPS_FILE)" ]; then echo "Nothing to remove ($(COMPOSE_APPS_FILE) does not exist)."; exit 0; fi; \
	if ! grep -q "# app:$$APP:begin" "$(COMPOSE_APPS_FILE)"; then \
		echo "App $$APP is not registered in $(COMPOSE_APPS_FILE)."; exit 0; \
	fi; \
	TMP=$$(mktemp); \
	awk -v app="$$APP" ' \
		$$0 ~ ("# app:" app ":begin") {skip=1} \
		!skip {print} \
		$$0 ~ ("# app:" app ":end") {skip=0} \
	' "$(COMPOSE_APPS_FILE)" > "$$TMP" && mv "$$TMP" "$(COMPOSE_APPS_FILE)"; \
	echo "App $$APP removed from $(COMPOSE_APPS_FILE)."

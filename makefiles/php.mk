# === PHP image build ===
DATE_TAG := $(shell date +%Y%m%d)
MAKEPHP_IMAGE ?= $(DOCKERHUB_USER)/makephp
BUILD_PLATFORMS ?= linux/amd64,linux/arm64

build: check-env
	@docker build $(if $(NO_CACHE),--no-cache) --pull \
		--build-arg PHP_ENABLE_SWOOLE=$(PHP_ENABLE_SWOOLE) \
		--build-arg PHP_ENABLE_XDEBUG=$(PHP_ENABLE_XDEBUG) \
		--target final -t $(PHP_IMAGE) -f ./php/Dockerfile ./php

build-prod: check-env
	@docker build $(if $(NO_CACHE),--no-cache) --pull \
		--build-arg PHP_ENABLE_SWOOLE=$(PHP_ENABLE_SWOOLE) \
		--target prod -t $(PHP_CONTAINER_NAME):8.3-prod -f ./php/Dockerfile ./php

rebuild-php:
	@echo "Rebuilding the php-fpm service without cache..."
	@docker compose build --no-cache php-fpm

# === DockerHub publishing (multi-arch) ===
# Requires a prior docker login to the $(DOCKERHUB_USER) account.
push-php: check-env
	@if [ -z "$(DOCKERHUB_USER)" ]; then \
		echo "Error: DOCKERHUB_USER is not set in .env"; exit 1; \
	fi
	@docker buildx inspect makephp-builder >/dev/null 2>&1 || \
		docker buildx create --name makephp-builder >/dev/null
	@echo "Publishing $(MAKEPHP_IMAGE):8.3-dev and :8.3-prod ($(BUILD_PLATFORMS))..."
	docker buildx build --builder makephp-builder --platform $(BUILD_PLATFORMS) \
		--build-arg PHP_ENABLE_SWOOLE=$(PHP_ENABLE_SWOOLE) \
		--target final \
		-t $(MAKEPHP_IMAGE):8.3-dev -t $(MAKEPHP_IMAGE):8.3-dev-$(DATE_TAG) \
		--push ./php
	docker buildx build --builder makephp-builder --platform $(BUILD_PLATFORMS) \
		--build-arg PHP_ENABLE_SWOOLE=$(PHP_ENABLE_SWOOLE) \
		--target prod \
		-t $(MAKEPHP_IMAGE):8.3-prod -t $(MAKEPHP_IMAGE):8.3-prod-$(DATE_TAG) \
		--push ./php
	@echo "Published. Verify with: docker buildx imagetools inspect $(MAKEPHP_IMAGE):8.3-dev"

# === Per-container helpers (suffix = container name) ===
shell:
	@echo "Error: use the suffixed form. Example: make shell-demo-app"; exit 1

shell-%:
	@docker exec -it $* zsh

artisan:
	@echo "Error: use the suffixed form. Example: make artisan-demo-app"; exit 1

artisan-%:
	@docker exec -it $* php artisan

composer:
	@echo "Error: use the suffixed form. Example: make composer-demo-app"; exit 1

composer-%:
	@docker exec -it $* composer

queue:
	@echo "Error: use the suffixed form. Example: make queue-demo-app"; exit 1

queue-%:
	@docker exec -it $* php artisan queue:work

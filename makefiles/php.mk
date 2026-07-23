# === PHP image build ===
DATE_TAG := $(shell date +%Y%m%d)
MAKEPHP_IMAGE ?= $(DOCKERHUB_USER)/makephp
BUILD_PLATFORMS ?= linux/amd64,linux/arm64

# PHP version derived from PHP_IMAGE_TAG (e.g. 8.4-dev -> 8.4).
# Override explicitly with: make build PHP_VERSION=8.5
PHP_VERSION_RAW := $(firstword $(subst -, ,$(PHP_IMAGE_TAG)))
PHP_VERSION ?= $(if $(filter 8.%,$(PHP_VERSION_RAW)),$(PHP_VERSION_RAW),8.3)
export PHP_VERSION
PHP_VERSIONS ?= 8.3 8.4 8.5

build: check-env
	@docker build $(if $(NO_CACHE),--no-cache) --pull \
		--build-arg PHP_VERSION=$(PHP_VERSION) \
		--build-arg PHP_ENABLE_SWOOLE=$(PHP_ENABLE_SWOOLE) \
		--build-arg PHP_ENABLE_XDEBUG=$(PHP_ENABLE_XDEBUG) \
		--target final -t $(PHP_CONTAINER_NAME):$(PHP_VERSION)-dev -f ./php/Dockerfile ./php
	@if [ "$(PHP_IMAGE)" != "$(PHP_CONTAINER_NAME):$(PHP_VERSION)-dev" ]; then \
		docker tag $(PHP_CONTAINER_NAME):$(PHP_VERSION)-dev $(PHP_IMAGE); \
	fi

build-prod: check-env
	@docker build $(if $(NO_CACHE),--no-cache) --pull \
		--build-arg PHP_VERSION=$(PHP_VERSION) \
		--build-arg PHP_ENABLE_SWOOLE=$(PHP_ENABLE_SWOOLE) \
		--target prod -t $(PHP_CONTAINER_NAME):$(PHP_VERSION)-prod -f ./php/Dockerfile ./php

rebuild-php:
	@echo "Rebuilding the php-fpm service without cache..."
	@docker compose build --no-cache --build-arg PHP_VERSION=$(PHP_VERSION) php-fpm

# === DockerHub publishing (multi-arch) ===
# Requires a prior docker login to the $(DOCKERHUB_USER) account.
# Publishes the version from PHP_IMAGE_TAG; override with PHP_VERSION=8.x
push-php: check-env
	@if [ -z "$(DOCKERHUB_USER)" ]; then \
		echo "Error: DOCKERHUB_USER is not set in .env"; exit 1; \
	fi
	@docker buildx inspect makephp-builder >/dev/null 2>&1 || \
		docker buildx create --name makephp-builder >/dev/null
	@echo "Publishing $(MAKEPHP_IMAGE):$(PHP_VERSION)-dev and :$(PHP_VERSION)-prod ($(BUILD_PLATFORMS))..."
	docker buildx build --builder makephp-builder --platform $(BUILD_PLATFORMS) \
		--build-arg PHP_VERSION=$(PHP_VERSION) \
		--build-arg PHP_ENABLE_SWOOLE=$(PHP_ENABLE_SWOOLE) \
		--target final \
		-t $(MAKEPHP_IMAGE):$(PHP_VERSION)-dev -t $(MAKEPHP_IMAGE):$(PHP_VERSION)-dev-$(DATE_TAG) \
		--push ./php
	docker buildx build --builder makephp-builder --platform $(BUILD_PLATFORMS) \
		--build-arg PHP_VERSION=$(PHP_VERSION) \
		--build-arg PHP_ENABLE_SWOOLE=$(PHP_ENABLE_SWOOLE) \
		--target prod \
		-t $(MAKEPHP_IMAGE):$(PHP_VERSION)-prod -t $(MAKEPHP_IMAGE):$(PHP_VERSION)-prod-$(DATE_TAG) \
		--push ./php
	@echo "Published. Verify with: docker buildx imagetools inspect $(MAKEPHP_IMAGE):$(PHP_VERSION)-dev"

# Publishes every version in PHP_VERSIONS, pruning the buildx cache between
# versions (dual-arch caches for multiple PHP versions exceed small disks).
push-php-all: check-env
	@for v in $(PHP_VERSIONS); do \
		echo "==== Publishing PHP $$v ===="; \
		$(MAKE) push-php PHP_VERSION=$$v || exit 1; \
		docker buildx prune -af --builder makephp-builder >/dev/null 2>&1 || true; \
	done
	@echo "All versions published: $(PHP_VERSIONS)"

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

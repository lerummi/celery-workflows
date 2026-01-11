MAKEFLAGS += --warn-undefined-variables --no-print-directory
.SHELLFLAGS := -eu -o pipefail -c

all: help
.PHONY: all

# Use bash for inline if-statements
SHELL:=bash

export APP_NAME := celery-workflows
APP_DESCRIPTION := Implementation of Workflows using Celery
APP_NAMESPACE := celery


##@ Hilfe
help: ## Zeige diese Hilfe an
	@echo "$(APP_NAME)"
	@echo "================================================="
	@echo "$(APP_DESCRIPTION)"
	@awk 'BEGIN {FS = ":.*##"; printf "\033[36m\033[0m"} /^[a-zA-Z0-9_%\/-]+:.*?##/ { printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
	@printf "\n"

##@ Docker
docker/build:  ## Baue docker images
	@echo "Baue docker images"
	docker compose build

##@ Helm
helm/package:  ## Helm Chart packagen
	helm package helm/ -d helm/charts

helm/upgrade:  ## Helm Upgrade
	helm upgrade --install $(APP_NAME) \
	     helm/charts/$(APP_NAME)-0.1.0.tgz \
		 -n $(APP_NAMESPACE) \
		 --create-namespace

helm/uninstall:  ## Helm uninstall
	helm uninstall celery-workflows -n $(APP_NAMESPACE)

##@ Kubernetes
k8s/get-all:
	kubectl get all -n $(APP_NAMESPACE)


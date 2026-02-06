MAKEFLAGS += --warn-undefined-variables --no-print-directory
.SHELLFLAGS := -eu -o pipefail -c

all: help
.PHONY: all

# Use bash for inline if-statements
SHELL:=bash

export APP_NAME := celery-workflows
APP_DESCRIPTION := Implementation of Workflows using Celery
APP_NAMESPACE := celery
ENV ?= local


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
helm/dep-update:  ## Update Helm dependencies
	helm dependency update ./helm

helm/package:  ## Helm Chart packagen
	rm -f helm/charts/$(APP_NAME)-0.1.0.tgz
	@helm package helm/ -d helm/charts

helm/upgrade:  ## Helm Upgrade (verwendet ENV=local|prod, default: local)
	helm upgrade --install $(APP_NAME) \
	     helm/charts/$(APP_NAME)-0.1.0.tgz \
		 -f helm/values.yaml \
		 -f helm/values/$(ENV).yaml \
		 -n $(APP_NAMESPACE) \
  		 --create-namespace

helm/upgrade-local:  ## Helm Upgrade für Local Environment
	$(MAKE) helm/upgrade ENV=local

helm/upgrade-prod:  ## Helm Upgrade für Production Environment
	$(MAKE) helm/upgrade ENV=prod

helm/uninstall:  ## Helm uninstall
	helm uninstall $(APP_NAME) -n $(APP_NAMESPACE)

##@ CSI Snapshots
csi/install-crds:  ## CSI Snapshot CRDs installieren (Prerequisite für Longhorn+Velero)
	kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
	kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml
	kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml

csi/install-controller:  ## CSI Snapshot Controller installieren
	kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml
	kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/master/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml

csi/install-all:  ## CSI CRDs + Controller installieren (Komplett-Setup)
	$(MAKE) csi/install-crds
	$(MAKE) csi/install-controller

##@ Velero
velero/install:  ## Velero Server installieren (einmalig, vor velero/enable)
	@printf '[default]\naws_access_key_id = accessKey\naws_secret_access_key = secretKey\n' > /tmp/velero-credentials
	velero install \
	  --provider aws \
	  --plugins velero/velero-plugin-for-aws \
	  --features=EnableCSI \
	  --no-default-backup-location \
	  --secret-file /tmp/velero-credentials \
	  --namespace $(APP_NAMESPACE)
	@rm -f /tmp/velero-credentials

velero/uninstall:  ## Velero Server entfernen
	velero uninstall --namespace $(APP_NAMESPACE) --force

velero/enable:  ## Velero aktivieren (BSL + Bucket-Init, ohne Schedule, verwendet ENV=local|prod)
	helm upgrade --install $(APP_NAME) \
	     helm/charts/$(APP_NAME)-0.1.0.tgz \
		 -f helm/values.yaml \
		 -f helm/values/$(ENV).yaml \
		 -n $(APP_NAMESPACE) --create-namespace \
		 --set velero.enabled=true

velero/backup:  ## Manuelles Backup starten (inkl. PVC Snapshots)
	velero backup create manual-$$(date +%s) \
	  --include-namespaces $(APP_NAMESPACE) \
	  --storage-location seaweedfs-bsl \
	  --snapshot-volumes=true \
	  -n $(APP_NAMESPACE)

velero/backup-list:  ## Alle Backups auflisten
	velero backup get -n $(APP_NAMESPACE)

velero/restore:  ## Restore aus Backup (BACKUP_NAME=<name> setzen)
	velero restore create --from-backup $(BACKUP_NAME) -n $(APP_NAMESPACE)

velero/schedule-enable:  ## Automatische Backups aktivieren (verwendet ENV=local|prod)
	helm upgrade --install $(APP_NAME) \
	     helm/charts/$(APP_NAME)-0.1.0.tgz \
		 -f helm/values.yaml \
		 -f helm/values/$(ENV).yaml \
		 -n $(APP_NAMESPACE) --create-namespace \
		 --set velero.enabled=true \
		 --set velero.schedule.enabled=true

velero/schedule-disable:  ## Automatische Backups deaktivieren (verwendet ENV=local|prod)
	helm upgrade --install $(APP_NAME) \
	     helm/charts/$(APP_NAME)-0.1.0.tgz \
		 -f helm/values.yaml \
		 -f helm/values/$(ENV).yaml \
		 -n $(APP_NAMESPACE) --create-namespace \
		 --set velero.enabled=true \
		 --set velero.schedule.enabled=false

##@ Kubernetes
k8s/get-all:  ## Alle Komponenten in kubernetes
	kubectl get all -n $(APP_NAMESPACE)


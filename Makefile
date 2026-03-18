CLUSTER_NAME := playground
KIND_CONFIG  := cluster/kind-config.yaml
KUBECTL      := kubectl --context kind-$(CLUSTER_NAME)
KEDA_VERSION := 2.19.0

# inotify limits required for multi-node Kind clusters
INOTIFY_MAX_USER_WATCHES   := 524288
INOTIFY_MAX_USER_INSTANCES := 512

.PHONY: create delete status preflight install-keda-crds gitea argocd fluxcd help

KYVERNO_ADMISSION_IMAGE    := ko.local/github.com/kyverno/kyverno/cmd/kyverno:5b0fbc8c2cbd1abf234d165c9915bf6a41f01aa389abb10b38a1a9e665c6267d
KYVERNO_BACKGROUND_IMAGE   := ko.local/github.com/kyverno/kyverno/cmd/background-controller:6fc45a8f2d181ad07c155b94b9b508b0f13e19f4f4fc56cd548252f7646bd988

create: preflight ## Create the Kind cluster and install Kyverno + Envoy Gateway
	@kind create cluster --name $(CLUSTER_NAME) --config $(KIND_CONFIG)
	@echo ""
	@echo " ⏳ Loading Kyverno images into Kind..."
	@kind load docker-image $(KYVERNO_ADMISSION_IMAGE) --name $(CLUSTER_NAME)
	@kind load docker-image $(KYVERNO_BACKGROUND_IMAGE) --name $(CLUSTER_NAME)
	@echo " ✓ Kyverno images loaded"
	@echo ""
	@$(MAKE) --no-print-directory install-keda-crds
	@$(MAKE) --no-print-directory -C cluster/kyverno deploy
	@$(MAKE) --no-print-directory -C cluster/envoy-gateway deploy

install-keda-crds: ## Install KEDA CRDs (without deploying KEDA itself)
	@echo " ⏳ Installing KEDA CRDs $(KEDA_VERSION)..."
	@$(KUBECTL) apply --server-side -f https://github.com/kedacore/keda/releases/download/v$(KEDA_VERSION)/keda-$(KEDA_VERSION)-crds.yaml > /dev/null
	@echo " ✓ KEDA CRDs installed"

delete: ## Delete the Kind cluster
	@kind delete cluster --name $(CLUSTER_NAME)

status: ## Show cluster info, Kyverno, and Envoy Gateway status
	@$(KUBECTL) cluster-info
	@echo ""
	@$(KUBECTL) get nodes
	@echo ""
	@$(MAKE) --no-print-directory -C cluster/kyverno status
	@echo ""
	@$(MAKE) --no-print-directory -C cluster/envoy-gateway status

preflight: ## Detect container runtime and ensure inotify limits are set
	@if colima status >/dev/null 2>&1; then \
		echo "Detected runtime: Colima"; \
		current_watches=$$(colima ssh -- sysctl -n fs.inotify.max_user_watches 2>/dev/null); \
		current_instances=$$(colima ssh -- sysctl -n fs.inotify.max_user_instances 2>/dev/null); \
		if [ "$$current_watches" -lt $(INOTIFY_MAX_USER_WATCHES) ] 2>/dev/null; then \
			echo "Setting fs.inotify.max_user_watches=$(INOTIFY_MAX_USER_WATCHES) (was $$current_watches)"; \
			colima ssh -- sudo sysctl -w fs.inotify.max_user_watches=$(INOTIFY_MAX_USER_WATCHES); \
		else \
			echo "fs.inotify.max_user_watches=$$current_watches (ok)"; \
		fi; \
		if [ "$$current_instances" -lt $(INOTIFY_MAX_USER_INSTANCES) ] 2>/dev/null; then \
			echo "Setting fs.inotify.max_user_instances=$(INOTIFY_MAX_USER_INSTANCES) (was $$current_instances)"; \
			colima ssh -- sudo sysctl -w fs.inotify.max_user_instances=$(INOTIFY_MAX_USER_INSTANCES); \
		else \
			echo "fs.inotify.max_user_instances=$$current_instances (ok)"; \
		fi; \
	elif docker info --format '{{.Name}}' 2>/dev/null | grep -qi desktop; then \
		echo "Detected runtime: Docker Desktop"; \
		current_watches=$$(docker run --rm --privileged alpine sysctl -n fs.inotify.max_user_watches 2>/dev/null); \
		current_instances=$$(docker run --rm --privileged alpine sysctl -n fs.inotify.max_user_instances 2>/dev/null); \
		if [ "$$current_watches" -lt $(INOTIFY_MAX_USER_WATCHES) ] 2>/dev/null; then \
			echo "Setting fs.inotify.max_user_watches=$(INOTIFY_MAX_USER_WATCHES) (was $$current_watches)"; \
			docker run --rm --privileged alpine sysctl -w fs.inotify.max_user_watches=$(INOTIFY_MAX_USER_WATCHES); \
		else \
			echo "fs.inotify.max_user_watches=$$current_watches (ok)"; \
		fi; \
		if [ "$$current_instances" -lt $(INOTIFY_MAX_USER_INSTANCES) ] 2>/dev/null; then \
			echo "Setting fs.inotify.max_user_instances=$(INOTIFY_MAX_USER_INSTANCES) (was $$current_instances)"; \
			docker run --rm --privileged alpine sysctl -w fs.inotify.max_user_instances=$(INOTIFY_MAX_USER_INSTANCES); \
		else \
			echo "fs.inotify.max_user_instances=$$current_instances (ok)"; \
		fi; \
	else \
		echo "ERROR: Could not detect Colima or Docker Desktop"; \
		exit 1; \
	fi

# --- Optional GitOps demos (not deployed by default) ---
# These demonstrate the "two loops" problem between GitOps controllers and Kyverno.
# See README.md > GitOps Integration Demo for the full walkthrough.

gitea: ## [Optional] Deploy Gitea in-cluster Git server
	@$(MAKE) --no-print-directory -C cluster/gitea deploy

argocd: ## [Optional] Deploy ArgoCD (requires: make gitea)
	@$(MAKE) --no-print-directory -C cluster/argocd deploy

fluxcd: ## [Optional] Deploy FluxCD with Web UI (requires: make gitea)
	@$(MAKE) --no-print-directory -C cluster/fluxcd deploy

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-18s %s\n", $$1, $$2}'

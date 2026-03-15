CLUSTER_NAME := playground
KIND_CONFIG  := kind-config.yaml
KUBECTL      := kubectl --context kind-$(CLUSTER_NAME)
KEDA_VERSION := 2.19.0

# inotify limits required for multi-node Kind clusters
INOTIFY_MAX_USER_WATCHES   := 524288
INOTIFY_MAX_USER_INSTANCES := 512

.PHONY: create delete status preflight install-keda-crds help

create: preflight ## Create the Kind cluster and install Kyverno + Envoy Gateway
	@kind create cluster --name $(CLUSTER_NAME) --config $(KIND_CONFIG)
	@echo ""
	@$(MAKE) --no-print-directory install-keda-crds
	@$(MAKE) --no-print-directory -C kyverno deploy
	@$(MAKE) --no-print-directory -C envoy-gateway deploy

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
	@$(MAKE) --no-print-directory -C kyverno status
	@echo ""
	@$(MAKE) --no-print-directory -C envoy-gateway status

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

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'

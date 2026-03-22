CONTEXT ?= kind-playground
KUBECTL := kubectl --context $(CONTEXT)
TIMEOUT := 300s

.PHONY: deploy destroy status demo help

deploy: ## Install Flux Operator + Flux Instance with Web UI (requires: make gitea from playground root)
	@echo " ⏳ Installing Flux Operator + Flux Instance..."
	@helmfile --file helmfile.yaml sync --quiet > /dev/null
	@$(KUBECTL) -n flux-system rollout status deployment/flux-operator --timeout=$(TIMEOUT) > /dev/null
	@echo " ⏳ Waiting for Flux controllers..."
	@$(KUBECTL) -n flux-system wait --for=condition=Ready fluxinstance/flux --timeout=$(TIMEOUT) > /dev/null 2>&1 || true
	@$(KUBECTL) -n flux-system rollout status deployment/source-controller --timeout=$(TIMEOUT) > /dev/null
	@$(KUBECTL) -n flux-system rollout status deployment/kustomize-controller --timeout=$(TIMEOUT) > /dev/null
	@$(KUBECTL) apply -k base/ > /dev/null
	@echo " ✓ FluxCD ready"
	@echo ""
	@echo "   Flux Web UI: http://flux.127.0.0.1.nip.io"

demo: ## Deploy GitRepository + platform and workloads Kustomizations (SSA — works out of the box with Kyverno)
	@echo " ⏳ Deploying Flux GitRepository + platform Kustomization (policies + namespace + ConfigMap)..."
	@$(KUBECTL) apply -f base/gitrepository.yaml > /dev/null
	@$(KUBECTL) apply -f base/kustomization-platform.yaml > /dev/null
	@$(KUBECTL) -n flux-system wait kustomization/example-02-platform \
		--for=condition=Ready \
		--timeout=$(TIMEOUT) > /dev/null
	@sleep 5 # wait for Kyverno to apply policies before deploying workloads
	@echo " ✓ Platform layer ready — policies and ConfigMap are in place"
	@echo ""
	@echo " ⏳ Deploying workloads Kustomization (ScaledObject)..."
	@$(KUBECTL) apply -f base/kustomization-ssa.yaml > /dev/null
	@echo " ✓ Flux resources deployed — Flux will reconcile both layers using Server-Side Apply"
	@echo ""
	@echo "   # Watch reconciliation status for both Kustomizations:"
	@echo "   kubectl -n flux-system get kustomization example-02-platform example-02-keda -w"
	@echo ""
	@echo "   # Verify the mutation is preserved:"
	@echo "   kubectl -n observability get scaledobject prometheus-scaledobject -o jsonpath='{.spec.triggers[0].metadata.serverAddress}'"
	@echo ""
	@echo "   # Or open the Flux Web UI: http://flux.127.0.0.1.nip.io"

demo-clean: ## Delete the demo resources and managed resources (reset between runs)
	@echo " ⏳ Cleaning up demo resources..."
	@$(KUBECTL) delete -f base/kustomization-ssa.yaml --ignore-not-found > /dev/null 2>&1
	@$(KUBECTL) delete -f base/kustomization-platform.yaml --ignore-not-found > /dev/null 2>&1
	@$(KUBECTL) delete -f base/gitrepository.yaml --ignore-not-found > /dev/null 2>&1
	@echo " ✓ Demo resources removed — Flux will prune all owned resources (policies, namespace, ScaledObject)"

destroy: demo-clean ## Remove FluxCD
	@$(KUBECTL) delete -k base/ --ignore-not-found > /dev/null 2>&1
	@helmfile --file helmfile.yaml destroy --quiet > /dev/null
	@echo " ✓ FluxCD removed"

status: ## Show FluxCD status
	@echo "=== Flux Pods ==="
	@$(KUBECTL) -n flux-system get pods
	@echo ""
	@echo "=== Flux Instance ==="
	@$(KUBECTL) -n flux-system get fluxinstance 2>/dev/null || echo "  (none)"
	@echo ""
	@echo "=== GitRepositories ==="
	@$(KUBECTL) -n flux-system get gitrepositories 2>/dev/null || echo "  (none)"
	@echo ""
	@echo "=== Kustomizations ==="
	@$(KUBECTL) -n flux-system get kustomizations 2>/dev/null || echo "  (none)"

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-18s %s\n", $$1, $$2}'

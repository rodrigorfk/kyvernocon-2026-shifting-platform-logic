CONTEXT ?= kind-playground
KUBECTL := kubectl --context $(CONTEXT)
TIMEOUT := 180s

.PHONY: deploy destroy status help

deploy: ## Install Kyverno
	@echo " ⏳ Installing Kyverno..."
	@helmfile --file helmfile.yaml sync --quiet > /dev/null
	@$(KUBECTL) -n kyverno rollout status deployment/kyverno-admission-controller --timeout=$(TIMEOUT) > /dev/null
	@$(KUBECTL) -n kyverno rollout status deployment/kyverno-background-controller --timeout=$(TIMEOUT) > /dev/null
	@$(KUBECTL) -n kyverno rollout status deployment/kyverno-cleanup-controller --timeout=$(TIMEOUT) > /dev/null
	@$(KUBECTL) -n kyverno rollout status deployment/kyverno-reports-controller --timeout=$(TIMEOUT) > /dev/null
	@echo " ✓ Kyverno ready"

destroy: ## Remove Kyverno
	@helmfile --file helmfile.yaml destroy --quiet > /dev/null
	@echo " ✓ Kyverno removed"

status: ## Show Kyverno status
	@echo "=== Kyverno Pods ==="
	@$(KUBECTL) -n kyverno get pods
	@echo ""
	@echo "=== MutatingPolicies ==="
	@$(KUBECTL) get mutatingpolicies -A 2>/dev/null || echo "  (none)"
	@echo ""
	@echo "=== ValidatingPolicies ==="
	@$(KUBECTL) get validatingpolicies -A 2>/dev/null || echo "  (none)"
	@echo ""
	@echo "=== GeneratingPolicies ==="
	@$(KUBECTL) get generatingpolicies -A 2>/dev/null || echo "  (none)"

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'

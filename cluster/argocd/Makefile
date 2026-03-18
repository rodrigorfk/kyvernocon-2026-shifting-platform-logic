CONTEXT   ?= kind-playground
KUBECTL   := kubectl --context $(CONTEXT)
KUSTOMIZE := kustomize build --load-restrictor=LoadRestrictionsNone
TIMEOUT   := 180s

.PHONY: deploy destroy status demo-broken demo-fix demo-clean help

deploy: ## Install ArgoCD (requires: make gitea from playground root)
	@echo " ⏳ Installing ArgoCD..."
	@helmfile --file helmfile.yaml sync --quiet > /dev/null
	@$(KUBECTL) -n argocd rollout status deployment/argocd-server --timeout=$(TIMEOUT) > /dev/null
	@$(KUBECTL) -n argocd rollout status deployment/argocd-repo-server --timeout=$(TIMEOUT) > /dev/null
	@$(KUBECTL) -n argocd rollout status statefulset/argocd-application-controller --timeout=$(TIMEOUT) > /dev/null
	@$(KUSTOMIZE) base/ | $(KUBECTL) apply -f - > /dev/null
	@echo " ✓ ArgoCD ready"
	@echo ""
	@echo "   ArgoCD UI: http://argocd.127.0.0.1.nip.io"
	@echo "   Password:  $$($(KUBECTL) -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo '(run: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d)')"

demo-broken: ## Deploy Application WITHOUT ServerSideDiff (shows the two-loops problem)
	@echo " ⏳ Deploying broken Application (client-side diff)..."
	@$(KUBECTL) apply -f base/application-broken.yaml
	@echo " ✓ Application deployed — watch for the reconciliation fight:"
	@echo ""
	@echo "   # Watch ArgoCD sync status (should flip between Synced/OutOfSync):"
	@echo "   kubectl -n argocd get app example-02-keda -w"
	@echo ""
	@echo "   # Watch the ScaledObject's serverAddress (should keep flipping):"
	@echo "   kubectl -n observability get scaledobject prometheus-scaledobject -o jsonpath='{.spec.triggers[0].metadata.serverAddress}' -w"
	@echo ""
	@echo "   # Or open the ArgoCD UI: http://argocd.127.0.0.1.nip.io"

demo-fix: ## Apply the fix: ServerSideDiff + IncludeMutationWebhook
	@echo " ⏳ Applying fixed Application (server-side diff + mutation webhook)..."
	@$(KUBECTL) apply -f base/application-fixed.yaml
	@echo " ✓ Fixed Application deployed"
	@echo ""
	@echo "   ArgoCD now uses server-side diff which accounts for Kyverno mutations."
	@echo "   The ScaledObject should show Synced + Healthy in the UI."

demo-clean: ## Delete the demo Application and observability namespace (reset between runs)
	@echo " ⏳ Cleaning up demo resources..."
	@$(KUBECTL) delete application example-02-keda -n argocd --ignore-not-found > /dev/null
	@$(KUBECTL) delete namespace observability --ignore-not-found > /dev/null
	@echo " ✓ Demo resources removed — ready for the next run"

destroy: ## Remove ArgoCD
	@$(KUBECTL) delete -f base/application-broken.yaml --ignore-not-found > /dev/null 2>&1
	@$(KUBECTL) delete -f base/application-fixed.yaml --ignore-not-found > /dev/null 2>&1
	@$(KUSTOMIZE) base/ | $(KUBECTL) delete --ignore-not-found -f - > /dev/null 2>&1
	@helmfile --file helmfile.yaml destroy --quiet > /dev/null
	@echo " ✓ ArgoCD removed"

status: ## Show ArgoCD status
	@echo "=== ArgoCD Pods ==="
	@$(KUBECTL) -n argocd get pods
	@echo ""
	@echo "=== ArgoCD Applications ==="
	@$(KUBECTL) -n argocd get applications 2>/dev/null || echo "  (none)"

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-18s %s\n", $$1, $$2}'

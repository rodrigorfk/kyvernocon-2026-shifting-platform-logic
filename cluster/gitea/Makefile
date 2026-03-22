CONTEXT  ?= kind-playground
KUBECTL  := kubectl --context $(CONTEXT)
KUSTOMIZE := kustomize build --load-restrictor=LoadRestrictionsNone
TIMEOUT  := 180s

.PHONY: deploy destroy status push-manifests help

deploy: ## Install Gitea and initialize the repository
	@echo " ⏳ Installing Gitea..."
	@helmfile --file helmfile.yaml sync --quiet > /dev/null
	@$(KUBECTL) -n gitea rollout status deployment/gitea --timeout=$(TIMEOUT) > /dev/null
	@echo " ✓ Gitea ready"
	@echo ""
	@echo " ⏳ Initializing Git repository..."
	@$(KUSTOMIZE) base/ | $(KUBECTL) apply -f - > /dev/null
	@$(KUBECTL) -n gitea wait --for=condition=complete job/init-repo --timeout=$(TIMEOUT) > /dev/null
	@echo " ✓ Repository initialized (http://gitea-http.gitea:3000/gitea/example-02.git)"
	@echo "   Repository contains: platform/ (policies + namespace + configmap) and workloads/ (ScaledObject)"
	@echo ""
	@echo "   Gitea UI: http://gitea.127.0.0.1.nip.io (gitea/gitea)"

destroy: ## Remove Gitea
	@$(KUSTOMIZE) base/ | $(KUBECTL) delete --ignore-not-found -f - > /dev/null 2>&1
	@helmfile --file helmfile.yaml destroy --quiet > /dev/null
	@echo " ✓ Gitea removed"

status: ## Show Gitea status
	@echo "=== Gitea ==="
	@$(KUBECTL) -n gitea get pods
	@echo ""
	@echo "=== Init Job ==="
	@$(KUBECTL) -n gitea get jobs

push-manifests: ## Re-push gitops-manifests to Gitea (deletes and recreates the init job)
	@$(KUBECTL) -n gitea delete job/init-repo --ignore-not-found > /dev/null
	@$(KUSTOMIZE) base/ | $(KUBECTL) apply -f - > /dev/null
	@$(KUBECTL) -n gitea wait --for=condition=complete job/init-repo --timeout=$(TIMEOUT) > /dev/null
	@echo " ✓ Manifests pushed to Gitea"

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-18s %s\n", $$1, $$2}'

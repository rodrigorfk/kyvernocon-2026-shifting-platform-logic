# FluxCD — It Just Works

Demonstrates that [FluxCD](https://fluxcd.io/) handles Kyverno mutating policies **out of the box** with no special configuration, in contrast to ArgoCD's default behavior.

Uses the [Flux Operator](https://github.com/controlplaneio-fluxcd/flux-operator) for a modern setup with the built-in **Flux Web UI**.

## What Gets Deployed

- **Flux Operator v0.45.0** — Manages Flux lifecycle + provides the Web UI on port 9080
- **Flux Instance** — Source controller + Kustomize controller (minimal, no Helm/notification/image controllers)
- **Gateway + HTTPRoute** — Exposes the Flux Web UI at `http://flux.127.0.0.1.nip.io`

## Why FluxCD Works Out of the Box

FluxCD uses **Server-Side Apply (SSA)** by default. When Flux detects drift, it performs an SSA dry-run against the Kubernetes API server. This dry-run triggers Kyverno's mutating admission webhook, so Flux sees the **post-mutation** state as the expected state:

```
                                          Flux SSA dry-run
Git manifest ──→ API Server ──→ Kyverno mutates ──→ Post-mutation result
                                                         ↕
                                                    Live state matches
                                                    → No drift detected
```

Compare this with ArgoCD's default **client-side diff**, which compares Git directly against the live state without running through webhooks — causing the two-loops problem.

## Prerequisites

1. The Kind cluster must be running with Kyverno installed (`make create` from the playground root)
2. Gitea must be deployed with the example-02 manifests (`make -C gitea deploy`)
3. If ArgoCD was previously tested, clean up its Applications first:
   ```bash
   kubectl -n argocd delete app example-02-keda example-02-platform --ignore-not-found
   kubectl delete ns observability --wait=false
   ```

## Demo Walkthrough

### 1. Deploy FluxCD

```bash
make deploy
```

### 2. Start reconciliation

```bash
make demo
```

This deploys a GitRepository and two Kustomizations: `example-02-platform` (policies + namespace + ConfigMap) and `example-02-keda` (ScaledObject).

### 3. Verify it works

Open `http://flux.127.0.0.1.nip.io` — you should see both Kustomizations with status **Ready**.

From the CLI:

```bash
# Both Kustomizations should show Ready=True
kubectl -n flux-system get kustomization example-02-platform example-02-keda

# The mutation is preserved — serverAddress reflects the ConfigMap value
kubectl -n observability get scaledobject prometheus-scaledobject \
  -o jsonpath='{.spec.triggers[0].metadata.serverAddress}'
# Output: http://prometheus-main.example.com:9090
```

No drift, no fighting, no special annotations. SSA handles it.

## Access

| Service | URL |
|---------|-----|
| Flux Web UI | `http://flux.127.0.0.1.nip.io` |
| Authentication | Anonymous (admin / system:masters) |

## Makefile Targets

| Target | Description |
|--------|-------------|
| `deploy` | Install Flux Operator + Flux Instance with Web UI |
| `destroy` | Remove FluxCD |
| `status` | Show Flux pods, instance, GitRepositories, Kustomizations |
| `demo` | Deploy GitRepository + platform and workloads Kustomizations (SSA, works out of the box) |
| `demo-clean` | Delete the Kustomizations and GitRepository; Flux prunes all owned resources (reset between runs) |
| `help` | List all targets |

## Comparison with ArgoCD

| Aspect | ArgoCD (default) | ArgoCD (fixed) | FluxCD |
|--------|-------------------|----------------|--------|
| Diff method | Client-side | Server-side | Server-side (SSA) |
| Mutation webhooks in diff | No | Yes (IncludeMutationWebhook) | Yes (SSA dry-run) |
| Works with Kyverno mutations | No (drift fight) | Yes | Yes |
| Special configuration needed | — | Annotation + sync option | None |

## File Structure

```
fluxcd/
├── Makefile                            # deploy, destroy, status, demo
├── helmfile.yaml                       # flux-operator v0.45.0 + flux-instance v0.45.0
├── values/
│   ├── flux-operator.yaml              # Web UI enabled, anonymous auth, insecure
│   └── flux-instance.yaml              # source + kustomize controllers only
├── base/
│   ├── kustomization.yaml              # Gateway resources
│   ├── gateway.yaml                    # Gateway + HTTPRoute (flux.127.0.0.1.nip.io)
│   ├── gitrepository.yaml              # Points to Gitea in-cluster repo
│   ├── kustomization-platform.yaml     # Flux Kustomization for platform/ (policies + namespace + ConfigMap)
│   └── kustomization-ssa.yaml          # Flux Kustomization for workloads/ (ScaledObject, SSA default)
└── README.md                           # This file
```

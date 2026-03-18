# Playground — Kyverno Policy Engine

A local Kubernetes environment for exploring Kyverno's new policy types (`MutatingPolicy`, `ValidatingPolicy`, `GeneratingPolicy`) using [Kind](https://github.com/kubernetes-sigs/kind/).
Built as a companion to the [KyvernoCon 2026 talk: **"Shifting Platform Logic into the Control Plane"**](https://colocatedeventseu2026.sched.com/event/2DY8H/kyverno-mutating-policies-shifting-platform-logic-into-the-control-plane-rodrigo-fior-kuntzer-miro?iframe=no&w=&sidebar=yes&bg=no).

## Cluster Topology

The Kind cluster runs 3 nodes (1 control-plane + 2 workers) on Kubernetes v1.35.1:

```
playground
├── control-plane (ingress-ready, hostPort 80 → 30080)
├── worker-1
└── worker-2
```

The control-plane node maps `hostPort:80 → containerPort:30080`. Envoy Gateway is deployed as a NodePort service on that port. A single shared `Gateway` resource (named `playground`) in `envoy-gateway-system` routes all `*.127.0.0.1.nip.io` traffic to in-cluster services. Each component registers its own `HTTPRoute` that attaches to this shared Gateway.

## What Gets Deployed

The `make create` target sets up the full environment:

1. **Kind cluster** — 3-node cluster with Kubernetes v1.35.1
2. **Kyverno v3.7.1** — Policy engine with admission, background, cleanup, and reports controllers (all single-replica)
3. **KEDA CRDs v2.19.0** — Only the CRDs (no KEDA operator), needed by Example 02
4. **Envoy Gateway v1.7.1** — Ingress controller with Gateway API support

## Prerequisites

- [Kind](https://kind.sigs.k8s.io/) v0.31+
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helmfile](https://helmfile.readthedocs.io/) + [Helm](https://helm.sh/)
- [Chainsaw](https://kyverno.github.io/chainsaw/) (for running tests)
- Container runtime: **Colima** or **Docker Desktop** (macOS)

## Quick Start

```bash
# Create the cluster (includes preflight checks + Kyverno + Envoy Gateway)
make create

# Check cluster status
make status

# Apply a policy example
kubectl apply -f 01-record-creation-details/

# Run that example's tests
cd 01-record-creation-details/.test && chainsaw test

# Tear it down
make delete
```

## Makefile Targets

| Target             | Description                                              |
|--------------------|----------------------------------------------------------|
| `create`           | Run preflight, create cluster, load images, install KEDA CRDs, deploy Kyverno + Envoy Gateway |
| `delete`           | Delete the Kind cluster                                  |
| `status`           | Show cluster info, Kyverno pods, policies, and Envoy Gateway |
| `install-keda-crds`| Install KEDA CRDs without deploying the KEDA operator    |
| `preflight`        | Detect container runtime and ensure inotify limits        |
| `gitea`            | [Optional] Deploy Gitea in-cluster Git server            |
| `argocd`           | [Optional] Deploy ArgoCD (requires: `make gitea`)        |
| `fluxcd`           | [Optional] Deploy FluxCD with Web UI (requires: `make gitea`) |
| `help`             | List all targets                                         |

## Preflight Checks

Running multiple Kind nodes requires higher inotify limits than the macOS VM defaults. The `preflight` target automatically:

1. Detects whether you're running **Colima** or **Docker Desktop**
2. Checks `fs.inotify.max_user_watches` and `fs.inotify.max_user_instances` inside the VM
3. Bumps them to `524288` / `512` if below threshold

Without this, kube-proxy and other components fail with `too many open files`.

## Policy Examples

Each numbered directory demonstrates a distinct Kyverno policy pattern. All examples include comprehensive [Chainsaw](https://kyverno.github.io/chainsaw/) tests in a `.test/` subdirectory.

### 01 — Record Creation Details

**Type:** MutatingPolicy + ValidatingPolicy

Adds a `kyverno.io/created-by` annotation to every ConfigMap at creation time, recording the requesting user's username. A companion ValidatingPolicy protects the annotation from modification or removal.

**Patterns demonstrated:** ApplyConfiguration mutation, CEL access to `request.userInfo`, immutable annotation enforcement.

### 02 — KEDA Prometheus Address

**Type:** MutatingPolicy (x2)

Bidirectional configuration propagation between a centralized ConfigMap and KEDA ScaledObjects:

- **ScaledObject policy** — When a ScaledObject is created/updated with the opt-in annotation `prometheus.keda.sh/use-central-serveraddress: "true"`, reads the Prometheus address from a ConfigMap and patches all prometheus-type triggers.
- **ConfigMap policy** — When the ConfigMap is updated, pushes the new address to all opted-in ScaledObjects in the cluster (mutateExisting).

**Patterns demonstrated:** Cross-resource lookups via `resource.Get()`, JSONPatch with `filter()` and `map()`, bidirectional sync, opt-in annotations.

### 03 — Pod Hardware Architecture

**Type:** MutatingPolicy

Automatically assigns a default CPU architecture (`nodeSelector: kubernetes.io/arch`) to newly created pods. The default is read from the namespace label `policies.kyverno.io/default-arch`, falling back to `arm64`.

**Patterns demonstrated:** Namespace-level configuration via labels, conditional skipping (DaemonSets, existing nodeSelector/affinity), fallback defaults, `resource.Get()` for namespace lookups.

### 04 — Image Registry Rewriting

**Type:** MutatingPolicy (x3)

Enforces private registry usage by rewriting container images at admission time:

- **Public registry policy** — Rewrites public registries (docker.io, gcr.io, ghcr.io, quay.io, public.ecr.aws, registry.k8s.io) to private ECR pull-through cache alternatives using a ConfigMap-driven mapping.
- **ECR cross-region policy** — Rewrites ECR images from other regions to the local region's registry.
- **Pull secret policy** — Injects `imagePullSecrets` for private registry proxy access.

**Patterns demonstrated:** CEL `image()` built-in for registry/repository/tag/digest parsing, ConfigMap-driven mappings, handling Docker Hub's implicit `library/` prefix, init container mutation.

### 05 — Deployment Registry Generation

**Type:** GeneratingPolicy (v1alpha1)

Watches Deployments labeled `kyverno.io/registry-provider: "true"` and generates ConfigMaps in a `registry-engine` namespace with registry integration status. Discovers matching Services via label selector comparison and checks for gRPC port availability.

**Patterns demonstrated:** GeneratingPolicy with `generator.Apply()`, `resource.List()` for service discovery, synchronization (downstream stays updated), orphaning on policy delete, complex CEL variable chains.

## GitOps Integration Demo

The playground includes optional **ArgoCD** and **FluxCD** configurations that demonstrate the interaction between GitOps controllers and Kyverno mutating policies — the classic ["two loops" problem](https://nirmata.com/2024/01/03/gitops-and-mutating-policies-the-tale-of-two-loops/).

### The Problem

When Kyverno mutates a resource at admission time (e.g., rewriting `serverAddress` in a ScaledObject), the live state diverges from the Git source of truth. GitOps controllers detect this as drift and try to revert it, creating an infinite reconciliation loop.

### The Demo

Uses Example 02 (KEDA Prometheus Address) as the test case, with an in-cluster [Gitea](https://gitea.io/) instance as the Git source.

```bash
# 1. Deploy Gitea — also applies the example-02 Kyverno policies (platform config)
make gitea

# 2. ArgoCD: show the broken behavior, then fix it
make argocd
make -C argocd demo-broken    # Watch the drift fight in the UI
make -C argocd demo-fix       # Apply ServerSideDiff fix

# 3. FluxCD: show it works out of the box
make fluxcd
make -C fluxcd demo           # SSA handles mutations natively
```

### UI Access

| Service | URL | Notes |
|---------|-----|-------|
| Gitea | `http://gitea.127.0.0.1.nip.io` | Credentials: `gitea` / `gitea` |
| ArgoCD | `http://argocd.127.0.0.1.nip.io` | Password: see `make -C argocd deploy` output |
| Flux Web UI | `http://flux.127.0.0.1.nip.io` | Anonymous access |

### Key Takeaway

| GitOps Tool | Default Behavior | Works with Kyverno? | Fix |
|-------------|------------------|----------------------|-----|
| ArgoCD | Client-side diff | No (drift fight) | `ServerSideDiff=true,IncludeMutationWebhook=true` |
| FluxCD | Server-Side Apply | Yes (out of the box) | None needed |

See [cluster/argocd/README.md](cluster/argocd/README.md) and [cluster/fluxcd/README.md](cluster/fluxcd/README.md) for detailed walkthroughs.

## Shared Test Infrastructure

The `fixtures/` directory contains a reusable Chainsaw `StepTemplate` that all examples reference. It creates a policy and asserts that both `WebhookConfigured` and `RBACPermissionsGranted` conditions are `True` before proceeding — ensuring the policy is fully operational before test assertions run.

## Directory Structure

```
playground/
├── Makefile                                    # Cluster lifecycle + optional GitOps targets
├── .tool-versions                              # Tool versions (kind 0.31.0)
├── README.md                                   # This file
│
├── fixtures/                                   # Shared Chainsaw StepTemplates (used by all .test/ suites)
│   └── create-policy-and-wait-ready.yaml
│
├── 01-record-creation-details/                 # Audit trail via annotations
│   ├── mutating-policy.yaml                    # Adds "created-by" annotation on ConfigMap creation
│   ├── validating-policy.yaml                  # Protects annotation from modification
│   └── .test/chainsaw-test.yaml                # Tests: create, protect, verify
│
├── 02-keda-prometheus-address/                 # Cross-resource config propagation
│   ├── mutating-policy-scaledobject.yaml       # ScaledObject → reads from ConfigMap
│   ├── mutating-policy-configmap.yaml          # ConfigMap → pushes to ScaledObjects
│   └── .test/chainsaw-test.yaml                # Tests: bidirectional sync
│
├── 03-pod-hardware-arch/                       # Intelligent pod defaults
│   ├── mutating-policy.yaml                    # Auto-assigns CPU arch from namespace labels
│   └── .test/chainsaw-test.yaml                # Tests: defaults, fallback, skipping
│
├── 04-image-registry/                          # Private registry enforcement
│   ├── mutating-policy-public.yaml             # Rewrites public → private ECR
│   ├── mutating-policy-ecr.yaml                # Rewrites ECR cross-region
│   ├── mutating-policy-pullsecret.yaml         # Injects imagePullSecrets
│   └── .test/chainsaw-test.yaml                # Tests: rewriting, secrets
│
├── 05-generate-deployment-registry/            # Declarative resource generation
│   ├── generating-policy.yaml                  # Generates ConfigMaps from Deployments
│   └── .test/chainsaw-test.yaml                # Tests: generation, sync, status
│
└── cluster/                                    # Cluster automation (Kind + Helm + GitOps tooling)
    ├── kind-config.yaml                        # Kind cluster definition (3 nodes, K8s v1.35.1)
    │
    ├── kyverno/                                # Kyverno Helm installation
    │   ├── Makefile                            # deploy, destroy, status, dev, dev-stop
    │   ├── helmfile.yaml                       # kyverno/kyverno v3.7.1
    │   ├── values/kyverno.yaml                 # Single replicas, extra RBAC
    │   └── dev-setup.sh                        # Local dev: TLS certs, webhook patching
    │
    ├── envoy-gateway/                          # Ingress controller
    │   ├── Makefile                            # deploy, destroy, status
    │   ├── helmfile.yaml                       # envoyproxy/gateway-helm v1.7.1
    │   ├── values/envoy-gateway.yaml           # GatewayClass controller name
    │   └── base/
    │       ├── kustomization.yaml
    │       └── gateway.yaml                    # EnvoyProxy (NodePort) + GatewayClass + shared Gateway + ReferenceGrant
    │
    ├── gitops-manifests/                       # Shared workload manifests for GitOps demos
    │   ├── kustomization.yaml
    │   ├── namespace.yaml                      # observability namespace
    │   ├── configmap.yaml                      # keda-prometheus-serveraddress
    │   └── scaledobject.yaml                   # ScaledObject with opt-in annotation
    │
    ├── gitea/                                  # In-cluster Git server
    │   ├── Makefile                            # deploy, destroy, status, push-manifests
    │   ├── helmfile.yaml                       # gitea-charts/gitea v12.5.0
    │   ├── values/gitea.yaml                   # SQLite, no SSH, admin gitea/gitea
    │   ├── base/
    │   │   ├── kustomization.yaml
    │   │   ├── init-repo-job.yaml              # Job: creates repo + pushes manifests
    │   │   └── gateway.yaml                    # HTTPRoute (gitea.127.0.0.1.nip.io → shared Gateway)
    │   └── README.md
    │
    ├── argocd/                                 # ArgoCD — two-loops demo
    │   ├── Makefile                            # deploy, destroy, status, demo-broken, demo-fix, demo-clean
    │   ├── helmfile.yaml                       # argo/argo-cd v9.4.12
    │   ├── values/argocd.yaml                  # Minimal: single replicas, no Dex, Gitea repo
    │   ├── base/
    │   │   ├── kustomization.yaml
    │   │   ├── gateway.yaml                    # HTTPRoute (argocd.127.0.0.1.nip.io → shared Gateway)
    │   │   ├── application-broken.yaml         # Client-side diff (shows drift fight)
    │   │   └── application-fixed.yaml          # ServerSideDiff + IncludeMutationWebhook
    │   └── README.md
    │
    └── fluxcd/                                 # FluxCD — works out of the box
        ├── Makefile                            # deploy, destroy, status, demo
        ├── helmfile.yaml                       # flux-operator + flux-instance v0.45.0
        ├── values/
        │   ├── flux-operator.yaml              # Web UI enabled, anonymous auth
        │   └── flux-instance.yaml              # source + kustomize controllers only
        ├── base/
        │   ├── kustomization.yaml
        │   ├── gateway.yaml                    # HTTPRoute (flux.127.0.0.1.nip.io → shared Gateway)
        │   ├── gitrepository.yaml              # Points to Gitea in-cluster repo
        │   └── kustomization-ssa.yaml          # Flux Kustomization (SSA default)
        └── README.md
```

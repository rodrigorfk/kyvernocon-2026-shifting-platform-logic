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

The control-plane node maps `hostPort:80 → containerPort:30080`. Envoy Gateway is deployed as a NodePort service on that port, enabling access to in-cluster services via `*.127.0.0.1.nip.io` hostnames from the host machine.

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

## Shared Test Infrastructure

The `00-tests-steps/` directory contains a reusable Chainsaw `StepTemplate` that all examples reference. It creates a policy and asserts that both `WebhookConfigured` and `RBACPermissionsGranted` conditions are `True` before proceeding — ensuring the policy is fully operational before test assertions run.

## Directory Structure

```
playground/
├── Makefile                                    # Cluster lifecycle (create, delete, status, preflight)
├── kind-config.yaml                            # Kind cluster definition (3 nodes, K8s v1.35.1)
├── .tool-versions                              # Tool versions (kind 0.31.0)
├── README.md                                   # This file
│
├── 00-tests-steps/
│   └── create-policy-and-wait-ready.yaml       # Reusable Chainsaw StepTemplate
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
├── kyverno/                                    # Kyverno Helm installation
│   ├── Makefile                                # deploy, destroy, status, dev, dev-stop
│   ├── helmfile.yaml                           # kyverno/kyverno v3.7.1
│   ├── values/kyverno.yaml                     # Single replicas, extra RBAC
│   └── dev-setup.sh                            # Local dev: TLS certs, webhook patching
│
└── envoy-gateway/                              # Ingress controller
    ├── Makefile                                # deploy, destroy, status
    ├── helmfile.yaml                           # envoyproxy/gateway-helm v1.7.1
    ├── values/envoy-gateway.yaml               # GatewayClass controller name
    └── base/
        ├── kustomization.yaml
        └── gateway.yaml                        # EnvoyProxy (NodePort) + GatewayClass
```

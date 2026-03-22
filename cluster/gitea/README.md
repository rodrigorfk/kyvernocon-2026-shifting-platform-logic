# Gitea — In-Cluster Git Server

A lightweight [Gitea](https://gitea.io/) instance deployed inside the Kind cluster, providing a real Git source for the ArgoCD and FluxCD GitOps demos. Uses SQLite for storage and runs as a single replica with no external dependencies.

## What Gets Deployed

- **Gitea v1.25.4** — Git server with web UI, SQLite backend, SSH disabled
- **Init Job** — Kubernetes Job that creates the `example-02` repository and pushes the `gitops-manifests/` content
- **Gateway + HTTPRoute** — Exposes the Gitea UI at `http://gitea.127.0.0.1.nip.io`

The repository is initialized with two subdirectories that reflect the split between platform and application concerns:

- `platform/` — Kyverno `MutatingPolicy` resources, the `observability` namespace, and the centralized Prometheus ConfigMap. Managed by the GitOps controller's platform Application/Kustomization.
- `workloads/` — The `ScaledObject` workload. This is the resource that demonstrates the two-loops problem with GitOps controllers.

## Quick Start

```bash
# Deploy Gitea and initialize the repository
make deploy

# Verify
make status
```

## Access

| Service | URL | Credentials |
|---------|-----|-------------|
| Gitea UI | `http://gitea.127.0.0.1.nip.io` | `gitea` / `gitea` |
| Git repo (in-cluster) | `http://gitea-http.gitea:3000/gitea/example-02.git` | — |

## Makefile Targets

| Target | Description |
|--------|-------------|
| `deploy` | Install Gitea and initialize the repository |
| `destroy` | Remove Gitea |
| `status` | Show Gitea pods and init job status |
| `push-manifests` | Re-push gitops-manifests to Gitea (deletes and recreates the init job) |
| `help` | List all targets |

## How the Init Job Works

The `init-repo` Job runs an `alpine/git` container that:

1. Waits for the Gitea HTTP API to become available (retry loop with `curl`)
2. Creates the `example-02` repository via the Gitea API
3. Clones the repo, copies manifests from a ConfigMap mount, commits, and pushes to `main`

The manifests are sourced from `../gitops-manifests/` (namespace, ConfigMap, workloads ScaledObject) and `../../02-keda-prometheus-address/` (Kyverno policy YAMLs), both mounted into the Job via a Kustomize `configMapGenerator`. The job script reconstructs the `platform/` and `workloads/` directory structure inside the repo. To update the manifests after changes, run `make push-manifests`.

## File Structure

```
gitea/
├── Makefile                        # deploy, destroy, status, push-manifests
├── helmfile.yaml                   # gitea-charts/gitea v12.5.0
├── values/
│   └── gitea.yaml                  # SQLite, no SSH, admin gitea/gitea
├── base/
│   ├── kustomization.yaml          # ConfigMap from gitops-manifests/ + Job + Gateway
│   ├── init-repo-job.yaml          # Job: creates repo + pushes manifests
│   └── gateway.yaml                # Gateway + HTTPRoute (gitea.127.0.0.1.nip.io)
└── README.md                       # This file
```

# ArgoCD — The Two-Loops Problem

Demonstrates the conflict between [ArgoCD](https://argo-cd.readthedocs.io/) and Kyverno mutating policies, and how to solve it using server-side diff.

Built as a companion to the [Nirmata blog post: "GitOps and Mutating Policies: The Tale of Two Loops"](https://nirmata.com/2024/01/03/gitops-and-mutating-policies-the-tale-of-two-loops/) and the [Kyverno platform notes for ArgoCD users](https://kyverno.io/docs/installation/platform-notes/#notes-for-argocd-users).

## What Gets Deployed

- **ArgoCD v3.3.4** — Application controller, server, repo-server (all single-replica)
- **Gateway + HTTPRoute** — Exposes the ArgoCD UI at `http://argocd.127.0.0.1.nip.io`
- Dex, Notifications, and ApplicationSet controllers are **disabled** to keep the installation minimal

## The Problem

When Kyverno mutates a resource at admission time, the live state diverges from the Git source of truth. ArgoCD's **default client-side diff** compares the Git manifest directly against the live object and flags any difference as drift:

```
Git (source of truth)                      Live (after Kyverno mutation)
─────────────────────                      ────────────────────────────
serverAddress:                             serverAddress:
  "http://my-prometheus:9090"       →        "http://prometheus-main:9090"
                                                      ↑
                                              Kyverno rewrote this from the
                                              centralized ConfigMap
```

With `selfHeal: true`, ArgoCD continuously reverts the mutation, Kyverno re-applies it, and the cycle repeats — the **two-loops problem**.

## The Solution

ArgoCD v2.10+ supports **server-side diff with mutation webhook inclusion**. Instead of comparing Git against the live state directly, ArgoCD sends the manifest through a server-side apply dry-run. This triggers Kyverno's mutating webhook, so the diff is computed against the **post-mutation** result:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/compare-options: ServerSideDiff=true,IncludeMutationWebhook=true
spec:
  syncPolicy:
    syncOptions:
      - ServerSideApply=true
```

The key annotation is `IncludeMutationWebhook=true` — without it, server-side diff skips mutation webhooks and the problem persists.

## Prerequisites

1. The Kind cluster must be running with Kyverno installed (`make create` from the playground root)
2. Gitea must be deployed with the example-02 manifests (`make -C gitea deploy`)
3. The Kyverno mutating policies must be applied (`kubectl apply -f 02-keda-prometheus-address/`)

## Demo Walkthrough

### 1. Deploy ArgoCD

```bash
make deploy
```

### 2. Show the broken behavior

```bash
make demo-broken
```

Open `http://argocd.127.0.0.1.nip.io` (user: `admin`, password shown in deploy output). You should see the `example-02-keda` Application flipping between **Synced** and **OutOfSync** as ArgoCD and Kyverno fight over the `serverAddress` field.

Watch it from the CLI:

```bash
# Sync status keeps flipping
kubectl -n argocd get app example-02-keda -w

# serverAddress keeps changing back and forth
kubectl -n observability get scaledobject prometheus-scaledobject \
  -o jsonpath='{.spec.triggers[0].metadata.serverAddress}' -w
```

### 3. Apply the fix

```bash
make demo-fix
```

The Application now uses server-side diff with `IncludeMutationWebhook=true`. ArgoCD's dry-run triggers Kyverno's webhook, so the post-mutation state matches expectations. The Application should show **Synced + Healthy**.

### 4. Verify the mutation is preserved

```bash
kubectl -n observability get scaledobject prometheus-scaledobject \
  -o jsonpath='{.spec.triggers[0].metadata.serverAddress}'
# Should output: http://prometheus-main.example.com:9090
```

## Access

| Service | URL |
|---------|-----|
| ArgoCD UI | `http://argocd.127.0.0.1.nip.io` |
| Username | `admin` |
| Password | `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' \| base64 -d` |

## Makefile Targets

| Target | Description |
|--------|-------------|
| `deploy` | Install ArgoCD (requires Gitea) |
| `destroy` | Remove ArgoCD and all Applications |
| `status` | Show ArgoCD pods and Applications |
| `demo-broken` | Deploy Application with client-side diff (shows drift fight) |
| `demo-fix` | Apply fix: ServerSideDiff + IncludeMutationWebhook |
| `help` | List all targets |

## File Structure

```
argocd/
├── Makefile                            # deploy, destroy, status, demo-broken, demo-fix
├── helmfile.yaml                       # argo/argo-cd v9.4.12
├── values/
│   └── argocd.yaml                     # Minimal: single replicas, no Dex, Gitea repo
├── base/
│   ├── kustomization.yaml              # Gateway resources
│   ├── gateway.yaml                    # Gateway + HTTPRoute (argocd.127.0.0.1.nip.io)
│   ├── application-broken.yaml         # Application with client-side diff (broken)
│   └── application-fixed.yaml          # Application with server-side diff (fixed)
└── README.md                           # This file
```

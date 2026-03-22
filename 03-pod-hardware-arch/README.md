# 03 — Pod Hardware Architecture

## Use Case

This use case demonstrates **platform-wide hardware architecture enforcement** with intelligent opt-out mechanisms. In clusters that mix `amd64` and `arm64` nodes, pods must declare their target architecture via `nodeSelector` to be scheduled correctly. Without enforcement, pods are often created without this constraint, leading to scheduling failures or unexpected behaviour.

A mutating policy automatically injects the appropriate `kubernetes.io/arch` nodeSelector into newly created pods based on a namespace-level label (`policies.kyverno.io/default-arch`), falling back to `arm64` when no label is set. The policy is designed to be non-intrusive: it respects several opt-out conditions to avoid overriding explicit user intent.

**Opt-out conditions (mutation is skipped when):**

- The namespace has enforcement disabled via label `policies.kyverno.io/disable-default-arch-enforcement: "true"`
- The pod already has an `kubernetes.io/arch` key in its `nodeSelector`
- The pod already declares architecture affinity (required or preferred) in `nodeAffinity`
- The pod is owned by a `DaemonSet` (which handles its own scheduling)

### Policies

| Policy | Type | Trigger | Action |
|--------|------|---------|--------|
| `mutate-pod-hardware-arch` | MutatingPolicy | Pod CREATE | Injects `kubernetes.io/arch` nodeSelector from namespace label, with `arm64` fallback |

## Chainsaw Test Suite

A complete Kyverno Chainsaw test suite is available inside the [.test](.test) folder. The test suite covers:

- Mutating a pod in a namespace with a `default-arch: amd64` label
- Falling back to `arm64` when the namespace has no arch label
- Merging the arch key into a pod that already has an unrelated nodeSelector
- Skipping mutation for namespaces with enforcement disabled
- Skipping mutation when the pod already specifies arch in `nodeSelector`
- Skipping mutation when the pod already specifies arch in `nodeAffinity`
- Skipping mutation for DaemonSet-owned pods

To run the tests, execute the following from the `.test` folder:

```sh
cd .test
chainsaw test
```

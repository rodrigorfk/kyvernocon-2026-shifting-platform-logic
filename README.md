# Kyverno Policy Migration Playground

## ClusterPolicy (JMESPath) → MutatingPolicy / GeneratingPolicy / ValidatingPolicy (CEL)

This playground contains 5 examples migrated from the legacy Kyverno `ClusterPolicy` CRD (`kyverno.io/v1`) to the new dedicated policy CRDs (`policies.kyverno.io/v1`) introduced in Kyverno v1.17, plus a local Kind cluster to test them.

**Original repository:** [rodrigorfk/k8s-kyverno-mutating-policies](https://github.com/rodrigorfk/k8s-kyverno-mutating-policies)

## Quick Start

### Prerequisites

- [Kind](https://kind.sigs.k8s.io/) v0.27+
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/)
- [Helmfile](https://github.com/helmfile/helmfile)
- Container runtime: [Colima](https://github.com/abiosoft/colima) or Docker Desktop

### Create the cluster

```bash
make create       # Creates Kind cluster + installs Kyverno v1.17.1 + Envoy Gateway
make status       # Verify everything is running
```

### Test a policy

```bash
kubectl apply -f 01-record-creation-details/mutating-policy.yaml
kubectl apply -f 01-record-creation-details/configmap.yaml
kubectl get configmap my-configmap -o jsonpath='{.metadata.annotations}'
```

### Tear down

```bash
make delete
```

### Components installed

| Component | Version | Chart |
|-----------|---------|-------|
| Kubernetes (Kind) | v1.35.1 | — |
| Kyverno | v1.17.1 | kyverno/kyverno 3.7.1 |
| Envoy Gateway | v1.7.1 | envoyproxy/gateway-helm 1.7.1 |

## Why Migrate?

Kyverno v1.17 (Jan 2026) marks the `ClusterPolicy` CRD as deprecated, with removal planned for v1.20 (Oct 2026). The new policy types offer:

- **Dedicated CRDs** for each action: `MutatingPolicy`, `ValidatingPolicy`, `GeneratingPolicy`, `DeletingPolicy`, `ImageValidatingPolicy`
- **CEL (Common Expression Language)** instead of JMESPath — aligning with the Kubernetes ecosystem
- **Extended CEL libraries**: `resource.Get()`, `http.Post()`, `image()`, `json.unmarshal()`, and more
- **Background mutation** with first-class support
- **Automatic MutatingAdmissionPolicy generation** (native K8s admission)

## Examples

| # | Example | Policy Types | Key CEL Features |
|---|---------|-------------|-----------------|
| 01 | [Record Creation Details](01-record-creation-details/) | MutatingPolicy + ValidatingPolicy | `request.userInfo`, `ApplyConfiguration`, `oldObject` |
| 02 | [KEDA Prometheus Address](02-keda-prometheus-address/) | 2x MutatingPolicy | `resource.Get()`, `enumerate().filter().map()`, background mutation |
| 03 | [Pod Hardware Architecture](03-pod-hardware-arch/) | MutatingPolicy | `namespaceObject`, `matchConditions`, `has()` checks |
| 04 | [Image Registry](04-image-registry/) | 3x MutatingPolicy | `image()` library, `http.Post()`, ConfigMap lookups, string operations |
| 05 | [Sidecar Injection](05-sidecar-inject/) | MutatingPolicy + GeneratingPolicy | `generator.Apply()`, rich `variables`, `ApplyConfiguration` |

## Migration Reference

| Concept | Legacy ClusterPolicy | New Policy CRDs |
|---------|---------------------|-----------------|
| API Version | `kyverno.io/v1` | `policies.kyverno.io/v1` |
| Expression Language | JMESPath | CEL |
| Resource Matching | `match.resources.kinds/operations` | `matchConstraints.resourceRules` |
| Conditions | `preconditions` | `matchConditions` (CEL expressions) |
| ConfigMap Access | `context.configMap` | `resource.Get("v1", "ConfigMap", ns, name)` |
| K8s API Calls | `context.apiCall` (GET/POST) | `resource.Get()` / `resource.List()` |
| External API Calls | `context.apiCall` with `service` | `http.Get()` / `http.Post()` |
| Merge Patch | `patchStrategicMerge` | `ApplyConfiguration` with `Object{}` |
| JSON Patch | `patchesJson6902` | `JSONPatch` with CEL expression |
| Iteration | `foreach` + `element` + `elementIndex` | CEL `enumerate().filter().map()` |
| Background Mutation | `mutate.targets` | `evaluation.background.enabled` |
| Resource Generation | `generate.data` | `generate` with `generator.Apply()` |
| Namespace Data | `apiCall` GET namespace | `namespaceObject` (built-in) |
| Image Parsing | `images.containers` context | `image()` CEL library |
| User Info | `request.userInfo \| to_string(@)` | `request.userInfo.username` / `.groups` |

## CEL Quick Reference

```cel
# Ternary (replaces JMESPath || fallback)
has(object.metadata.labels) && "key" in object.metadata.labels
  ? object.metadata.labels["key"]
  : "default-value"

# Resource lookup (replaces context.configMap)
resource.Get("v1", "ConfigMap", "namespace", "name").data["key"]

# Image parsing (replaces images.containers context)
image("nginx:latest").registry    // "docker.io"
image("nginx:latest").path        // "library/nginx"
image("nginx:latest").tag         // "latest"

# Iteration with index (replaces foreach + elementIndex)
object.spec.containers.enumerate().filter(e,
  e.value.image.startsWith("public.ecr.aws")
).map(e,
  {"op": "replace", "path": "/spec/containers/" + string(e.index) + "/image", "value": "..."}
)

# HTTP call (replaces apiCall with service)
http.Post("http://service:8080/api/check", {"key": "value"}).body

# Namespace access (replaces apiCall GET namespace)
namespaceObject.metadata.labels["my-label"]
```

## Known Limitations & TODOs

1. **Background cross-resource mutation** (Example 02, rule 2): The exact syntax for "when ConfigMap changes, mutate existing ScaledObjects" in the new MutatingPolicy CRD needs verification against Kyverno v1.17.
2. **HTTP calls inside iteration** (Example 04, ECR policy): Calling `http.Post()` inside a `map()` expression may not be supported in CEL. If not, the policy needs restructuring.
3. **Object construction depth** (Example 05): Very large `ApplyConfiguration` expressions with deeply nested objects (probes, lifecycle hooks) may hit expression complexity limits.
4. All uncertain patterns are marked with `# TODO: verify against Kyverno v1.17` in the policy files.

## Documentation

- [Policy Types Overview](https://kyverno.io/docs/policy-types/overview/)
- [MutatingPolicy](https://kyverno.io/docs/policy-types/mutating-policy/)
- [GeneratingPolicy](https://kyverno.io/docs/policy-types/generating-policy/)
- [CEL Libraries](https://kyverno.io/docs/policy-types/cel-libraries/)
- [ClusterPolicy (Legacy)](https://kyverno.io/docs/policy-types/cluster-policy/overview/)

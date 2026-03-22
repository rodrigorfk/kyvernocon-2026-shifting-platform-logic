# 01 — Record Creation Details

## Use Case

This use case demonstrates how to implement an **immutable audit trail** at the Kubernetes API level using Kyverno policies. When a ConfigMap is created, a mutating policy automatically records the identity of the creator by injecting a `kyverno.io/created-by` annotation. A validating policy then protects that annotation from being modified or removed by any subsequent update — ensuring the audit record remains trustworthy and tamper-proof.

This pattern is useful for compliance and governance scenarios where teams need to know who originally created a resource, without relying on external audit systems or manual conventions.

> **Note:** This policy requires a bugfix not yet included in a stable Kyverno release. The playground is configured to use a pinned `main` branch image to include [kyverno/kyverno#15589](https://github.com/kyverno/kyverno/pull/15589).

### Policies

| Policy | Type | Trigger | Action |
|--------|------|---------|--------|
| `record-creation-details` | MutatingPolicy | ConfigMap CREATE | Injects `kyverno.io/created-by` annotation with the requesting user's username |
| `record-creation-details-protect` | ValidatingPolicy | ConfigMap UPDATE | Denies any update that attempts to add, change, or remove the `kyverno.io/created-by` annotation |

## Chainsaw Test Suite

A complete Kyverno Chainsaw test suite is available inside the [.test](.test) folder. The test suite covers:

- Creating a ConfigMap and asserting that the `kyverno.io/created-by` annotation is automatically injected
- Attempting to add the annotation manually (denied)
- Attempting to change the annotation value (denied)
- Attempting to remove the annotation (denied)

To run the tests, execute the following from the `.test` folder:

```sh
cd .test
chainsaw test
```

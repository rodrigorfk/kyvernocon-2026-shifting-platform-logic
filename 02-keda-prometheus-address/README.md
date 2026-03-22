# 02 — KEDA Prometheus Address

## Use Case

This use case demonstrates a **bidirectional configuration synchronisation** pattern using two complementary mutating policies. Platform teams often maintain a central Prometheus server address that KEDA `ScaledObjects` need to reference. Rather than requiring every team to hardcode this address, Kyverno policies keep all opt-in `ScaledObjects` in sync automatically.

The synchronisation works in both directions:

1. **Pull (on resource creation):** When a new `ScaledObject` with the opt-in annotation `prometheus.keda.sh/use-central-serveraddress: "true"` is created, Kyverno reads the current Prometheus address from a central ConfigMap and injects it into the `ScaledObject`'s prometheus triggers.
2. **Push (on config change):** When the central ConfigMap is updated, Kyverno propagates the new address to all existing opt-in `ScaledObjects` using `mutateExisting`.

This pattern shifts configuration management into the control plane, eliminating manual updates and configuration drift across teams.

> **Note:** This policy requires bugfixes not yet included in a stable Kyverno release. The playground is configured to use a pinned `main` branch image to include [kyverno/kyverno#15669](https://github.com/kyverno/kyverno/pull/15669) and [kyverno/kyverno#15693](https://github.com/kyverno/kyverno/pull/15693).

### Policies

| Policy | Type | Trigger | Action |
|--------|------|---------|--------|
| `keda-prometheus-serveraddress-scaledobject` | MutatingPolicy | ScaledObject CREATE/UPDATE | Reads central ConfigMap and patches prometheus trigger `serverAddress` fields |
| `keda-prometheus-serveraddress-configmap` | MutatingPolicy | ConfigMap UPDATE in `observability` namespace | Propagates the updated address to all opt-in `ScaledObjects` cluster-wide |

## Chainsaw Test Suite

A complete Kyverno Chainsaw test suite is available inside the [.test](.test) folder. The test suite covers:

- Creating a `ScaledObject` with the opt-in annotation and asserting that the Prometheus address is injected
- Updating the central ConfigMap and asserting that opt-in `ScaledObjects` are updated automatically
- Creating a `ScaledObject` without the opt-in annotation and asserting that it is left unchanged

To run the tests, execute the following from the `.test` folder:

```sh
cd .test
chainsaw test
```

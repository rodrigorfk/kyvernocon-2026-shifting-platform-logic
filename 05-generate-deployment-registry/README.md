# 05 — Generate Deployment Registry

## Use Case

This use case demonstrates **automatic metadata generation and service discovery** using a `GeneratingPolicy`. A central registry engine needs to know which Deployments in the cluster expose a gRPC interface, so it can configure itself to communicate with them. Rather than requiring application teams to manually register their services, Kyverno watches for opt-in Deployments and automatically generates ConfigMaps in the `registry-engine` namespace reflecting each service's readiness.

When a Deployment labelled with `kyverno.io/registry-provider: "true"` is created or updated, Kyverno:

1. Looks for a Service in the same namespace whose selector matches the Deployment's pod template labels.
2. Checks whether that Service exposes a port with `appProtocol: grpc`.
3. Generates a ConfigMap named `registry-<namespace>-<deployment-name>` in the `registry-engine` namespace with:
   - `enabled: "true"` and the full `grpcAddress` (`<service>.<namespace>.svc.cluster.local:<port>`) — if a matching gRPC service is found.
   - `enabled: "false"` and a human-readable reason — if no matching Service or gRPC port is found.

The generated ConfigMaps are kept in sync (`synchronize: true`) as Deployments and Services change, and are preserved even if the policy is deleted (`orphanDownstreamOnPolicyDelete: true`).

### Policies

| Policy | Type | Trigger | Action |
|--------|------|---------|--------|
| `registry-generation-policy` | GeneratingPolicy | Deployment CREATE/UPDATE (with `kyverno.io/registry-provider: "true"` label) | Generates a ConfigMap in `registry-engine` namespace with gRPC discovery metadata |

## Chainsaw Test Suite

A complete Kyverno Chainsaw test suite is available inside the [.test](.test) folder. The test suite covers:

- Creating a Deployment with a matching Service that exposes a gRPC port and asserting that the ConfigMap is generated with `enabled: "true"` and the correct `grpcAddress`
- Creating a Deployment without a matching Service and asserting that the ConfigMap is generated with `enabled: "false"` and an explanatory reason
- Creating a Deployment with a Service that lacks a gRPC `appProtocol` and asserting the ConfigMap reflects the missing protocol
- Updating a Service to add a gRPC port and asserting the ConfigMap is synchronised automatically

To run the tests, execute the following from the `.test` folder:

```sh
cd .test
chainsaw test
```

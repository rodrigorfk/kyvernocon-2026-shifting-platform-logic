# 06 — Pod Invalid Schema

## Use Case

This use case demonstrates **schema compliance recovery** at the Kubernetes API level. In certain development or migration scenarios, tools or controllers may submit Pod specs that are missing required fields — such as the `image` field on a container. Without intervention, these requests are rejected by the API server, causing confusing errors.

A mutating policy intercepts Pod CREATE requests and detects containers that have a `name` but are missing the required `image` field. When this condition is met, Kyverno patches the pod by setting the container's `image` to the same value as its `name`, applying a sensible default that allows the pod to be accepted and scheduled. Pods with a valid and complete schema are left untouched.

This pattern is useful for platform teams who want to provide a more lenient developer experience or support legacy tooling while keeping Kubernetes schema integrity intact at the infrastructure level.

### Policies

| Policy | Type | Trigger | Action |
|--------|------|---------|--------|
| `mutate-pod-invalid-schema` | MutatingPolicy | Pod CREATE | Adds the missing `image` field (set to the container `name`) when a container is missing `image` |

## Chainsaw Test Suite

A complete Kyverno Chainsaw test suite is available inside the [.test](.test) folder. The test suite covers:

- Creating a pod with a container missing the `image` field and asserting that the image is automatically set to the container name
- Creating a pod with a valid schema and asserting that it is not mutated

To run the tests, execute the following from the `.test` folder:

```sh
cd .test
chainsaw test
```

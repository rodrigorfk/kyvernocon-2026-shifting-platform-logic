# 04 — Image Registry

## Use Case

This use case demonstrates **centralised image registry enforcement** using three complementary mutating policies that work together to route all container images through corporate registries. This pattern is common in organisations that need to enforce security scanning, control egress traffic, or comply with supply chain requirements — without requiring application teams to change their manifests.

The three policies address distinct scenarios:

1. **ECR cross-region rewriting:** When a pod references an ECR image from a different AWS region, Kyverno rewrites the image URL to use the local region's ECR pull-through cache, avoiding cross-region data transfer costs and latency. The local region is read dynamically from a ConfigMap in `kube-system`.

2. **Public registry rewriting:** When a pod references a public registry (e.g., `docker.io`, `ghcr.io`, `gcr.io`, `quay.io`, `registry.k8s.io`, `public.ecr.aws`) without pre-existing image pull secrets, Kyverno rewrites the image to the corresponding private ECR pull-through cache path. The registry mappings are stored centrally in a ConfigMap.

3. **ImagePullSecret injection:** When a pod uses images from the private registry proxy, Kyverno automatically injects the required `imagePullSecret`, so teams do not need to manage secret references in their workload manifests.

### Policies

| Policy | Type | Trigger | Action |
|--------|------|---------|--------|
| `01-mutate-ecr-cross-region` | MutatingPolicy | Pod CREATE | Rewrites ECR images from foreign regions to the local region's pull-through cache |
| `02-mutate-public-registry-containers` | MutatingPolicy | Pod CREATE (no imagePullSecrets) | Rewrites public registry images to private ECR pull-through cache equivalents |
| `03-mutate-imagepullsecret-injection` | MutatingPolicy | Pod CREATE | Injects `registry-proxy-private-key` imagePullSecret for pods using the private registry proxy |

## Chainsaw Test Suite

A complete Kyverno Chainsaw test suite is available inside the [.test](.test) folder. The test suite covers:

- Rewriting images from all supported public registries (docker.io, ghcr.io, gcr.io, quay.io, registry.k8s.io, public.ecr.aws)
- Handling docker.io edge cases (unqualified images, library namespace, digests)
- Pods with multiple containers and mixed registries
- ECR cross-region rewriting for containers and initContainers
- ImagePullSecret injection for private registry proxy images
- Asserting that pods with existing `imagePullSecrets` are not mutated by the public registry policy
- Asserting that images from unknown registries are not modified

To run the tests, execute the following from the `.test` folder:

```sh
cd .test
chainsaw test
```

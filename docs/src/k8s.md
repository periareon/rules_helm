# Kubernetes tools

`rules_helm` can fetch `kubectl` the same way it fetches `helm`, so a release
driven by [helm_install](./helm_install.md#helm_install) or
[helm_upgrade](./helm_install.md#helm_upgrade) can be inspected from the same
workspace without installing anything on the host. Everyone on a project gets
the same `kubectl` version, on every platform Bazel runs on.

## Setup

`rules_helm` registers the `kubectl` toolchains itself. To get the `@kubectl`
repository for `bazel run`, add the extension to your `MODULE.bazel`:

```python
k8s = use_extension("@rules_helm//k8s:extensions.bzl", "k8s")
k8s.kubectl()
use_repo(k8s, "kubectl")
```

## Debugging a helm deploy

`bazel run` passes your environment through, so `KUBECONFIG`, `~/.kube/config`
and the usual `--context` / `--namespace` flags behave exactly as they do for a
locally installed `kubectl`.

```bash
# Roll out the release
bazel run //deploy:my_chart.install

# What did helm do?
bazel run @helm//:helm -- status my-release
bazel run @helm//:helm -- history my-release
bazel run @helm//:helm -- get manifest my-release

# What is the cluster doing with it?
bazel run @kubectl//:kubectl -- get pods --namespace my-namespace
bazel run @kubectl//:kubectl -- describe deployment my-release
bazel run @kubectl//:kubectl -- logs deployment/my-release --tail 100
bazel run @kubectl//:kubectl -- get events --sort-by=.lastTimestamp
```

## Use in a genrule

The resolved toolchain exposes the binary as the `KUBECTL_BIN` make variable:

```python
genrule(
    name = "kubectl_version",
    outs = ["kubectl_version.json"],
    cmd = "$(KUBECTL_BIN) version --client --output json > $@",
    toolchains = ["@rules_helm//k8s:current_kubectl_toolchain"],
)
```

## Pinning a version

`rules_helm` ships checksums for a single default `kubectl` version. Clusters
that are more than one minor version away from it should pin a matching
release, which the root module can do with the `version` attribute:

```python
k8s.kubectl(version = "1.36.5")
```

Checksums for versions `rules_helm` does not know about are looked up from the
upstream `.sha256` files while the extension is evaluated. On Bazel 8.5 and newer
the digests are then stored as facts in `MODULE.bazel.lock`, so the lookup
happens once per version and airgapped builds keep working from the lockfile.
Older Bazel versions repeat the lookup whenever the extension is re-evaluated.

Several versions can live side by side by giving each tag its own repository
name. Only the first `kubectl` tag in the root module decides which version the
registered toolchains serve:

```python
k8s.kubectl()
k8s.kubectl(name = "kubectl_legacy", version = "1.35.6")
use_repo(k8s, "kubectl", "kubectl_legacy")
```

```bash
bazel run @kubectl_legacy//:kubectl -- get nodes
```

## For rule authors

Rules that need `kubectl` in an action depend on the
`@rules_helm//k8s:kubectl_toolchain_type` toolchain type and read the binary
from `ctx.toolchains[...].kubectl`. See [kubectl_toolchain](./k8s_defs.md#kubectl_toolchain)
for the provider fields and the [k8s extension](./k8s_extensions.md) for the
`MODULE.bazel` API.

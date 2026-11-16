# Container images

A chart's `images` attribute accepts push targets from
[rules_oci](https://github.com/bazel-contrib/rules_oci) and
[rules_img](https://github.com/bazel-contrib/rules_img), and `rules_helm`
stamps the pushed repository and digest into the chart. `rules_helm` itself
depends on neither. Each is wired up by a companion module that lives in this
repository under [extensions/](https://github.com/periareon/rules_helm/tree/main/extensions)
and is released from the same tag, with the same version, as `rules_helm`.

| Module | Depends on | Load from |
| --- | --- | --- |
| `rules_helm_img` | `rules_img` | `@rules_helm_img//:defs.bzl` |
| `rules_helm_oci` | `rules_oci` | `@rules_helm_oci//:defs.bzl` |

As in `rules_helm`, each rule also has its own file next to `defs.bzl`, e.g.
`@rules_helm_img//:helm_img_image.bzl`, for `BUILD` files that only want one
thing.

Each module re-exports every public symbol of `@rules_helm//helm:defs.bzl`
plus the push rule its image rules provide (`image_push` or `oci_push`), so a
chart that bundles images is written against one `load`. Rules that are
specific to one set of image rules land in its module rather than in
`rules_helm`.

## The contract

`rules_helm` reads one thing from an image:
[HelmImageInfo](./helm_image.md#HelmImageInfo). It carries the label values
refer to, a repository file, the raw manifest whose sha256 is the digest, the
remote tags, and the executable that pushes the image. `helm_package.images`
accepts any target that provides it.

Three things provide it today:

- `rules_helm` itself, for `oci_push`, `image_push` and `image_import` targets
  listed directly in `images`. An aspect recognises them by shape and reads
  their attributes, which is all it can do without depending on either
  ruleset. This is what keeps existing charts working unchanged.
- [helm_img_image](./helm_img_image.md#helm_img_image) from `rules_helm_img`
  and [helm_oci_image](./helm_oci_image.md#helm_oci_image) from
  `rules_helm_oci`. These read the image rules' own providers (`DeployInfo`
  and `PullInfo` in the case of `rules_img`) and are the preferred path for
  new charts. Values keep referring to the wrapped push target.
- [helm_image](./helm_image.md#helm_image) from `rules_helm`, which takes the
  files directly, for images built by something else entirely.

## Setup

```python
bazel_dep(name = "rules_helm_img", version = "{version}")
```

A `bazel_dep` on the companion module pulls in `rules_helm`, so it does not
need to be listed separately. The rules for building the images themselves
(`image_manifest`, `oci_image` and friends) are still loaded from `rules_img`
or `rules_oci`, which means a direct `bazel_dep` on whichever one you use.

## Example

```python
load("@rules_helm_img//:defs.bzl", "helm_chart", "helm_img_image", "image_push")
load("@rules_img//img:image.bzl", "image_manifest")

image_manifest(
    name = "app",
    layers = [":app_layer"],
)

image_push(
    name = "app.push",
    image = ":app",
    registry = "docker.io",
    repository = "my-org/app",
    tags = ["latest"],
)

helm_img_image(
    name = "app.helm",
    image = ":app.push",
)

helm_chart(
    name = "chart",
    images = [":app.helm"],
)
```

With `values.yaml` referencing the push target by label:

```yaml
image: "{@//:app.push}"
```

The packaged chart carries `docker.io/my-org/app@sha256:...` in its place.

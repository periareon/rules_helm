"""# Helm images

`HelmImageInfo` is the contract between `rules_helm` and the rules that build
container images. `helm_package.images` accepts any target that provides it.

`rules_helm` provides it itself for `oci_push`, `image_push` and `image_import`
targets by recognising them by shape. The companion modules provide it from
the image rules' own providers instead:

- `rules_helm_img`: `helm_img_image`
- `rules_helm_oci`: `helm_oci_image`

`helm_image` is the reference implementation for anything else.
"""

load(
    "//helm/private:image_utils.bzl",
    _helm_image = "helm_image",
)
load(
    "//helm/private:providers.bzl",
    _HelmImageInfo = "HelmImageInfo",
)

HelmImageInfo = _HelmImageInfo
helm_image = _helm_image

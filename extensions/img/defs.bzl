"""# rules_helm_img

Helm rules for charts whose images are built with
[rules_img](https://github.com/bazel-contrib/rules_img).

`rules_helm` does not depend on `rules_img`. This module does, so a chart that
bundles `rules_img` images can get a compatible version of both from one
dependency and write its `BUILD` file against one `load`:

```python
load("@rules_helm_img//:defs.bzl", "helm_chart", "image_push")
```

Every public symbol of `@rules_helm//helm:defs.bzl` is re-exported here, along
with `image_push`, the `rules_img` rule whose targets `helm_chart.images`
accepts. Rules for building the images themselves (`image_manifest`,
`image_layer`, `pull`, ...) are loaded from `rules_img` directly.

`helm_img_image` is this module's implementation of `HelmImageInfo`. It reads
`rules_img`'s own `DeployInfo` and `PullInfo` providers rather than guessing at
a target's attributes, which is what `rules_helm` has to do on its own.
"""

load(
    "@rules_img//img:push.bzl",
    _image_push = "image_push",
)
load(
    ":chart_file.bzl",
    _chart_content = "chart_content",
    _chart_file = "chart_file",
)
load(
    ":helm_chart.bzl",
    _helm_chart = "helm_chart",
)
load(
    ":helm_command.bzl",
    _helm_command = "helm_command",
)
load(
    ":helm_image.bzl",
    _HelmImageInfo = "HelmImageInfo",
    _helm_image = "helm_image",
)
load(
    ":helm_img_image.bzl",
    _helm_img_image = "helm_img_image",
)
load(
    ":helm_import.bzl",
    _helm_import = "helm_import",
    _helm_import_repository = "helm_import_repository",
)
load(
    ":helm_install.bzl",
    _helm_install = "helm_install",
    _helm_uninstall = "helm_uninstall",
    _helm_upgrade = "helm_upgrade",
)
load(
    ":helm_lint.bzl",
    _helm_lint_aspect = "helm_lint_aspect",
    _helm_lint_test = "helm_lint_test",
)
load(
    ":helm_oci_digest.bzl",
    _HelmOCIDigestInfo = "HelmOCIDigestInfo",
    _helm_oci_digest = "helm_oci_digest",
)
load(
    ":helm_oci_manifest.bzl",
    _helm_oci_manifest = "helm_oci_manifest",
)
load(
    ":helm_package.bzl",
    _helm_package = "helm_package",
)
load(
    ":helm_package_info.bzl",
    _HelmPackageInfo = "HelmPackageInfo",
)
load(
    ":helm_plugin.bzl",
    _helm_plugin = "helm_plugin",
)
load(
    ":helm_push.bzl",
    _helm_push = "helm_push",
    _helm_push_images = "helm_push_images",
    _helm_push_registry = "helm_push_registry",
)
load(
    ":helm_template.bzl",
    _helm_template = "helm_template",
    _helm_template_test = "helm_template_test",
)
load(
    ":helm_toolchain.bzl",
    _helm_toolchain = "helm_toolchain",
)

chart_content = _chart_content
chart_file = _chart_file
helm_chart = _helm_chart
helm_command = _helm_command
helm_image = _helm_image
helm_import = _helm_import
helm_import_repository = _helm_import_repository
helm_install = _helm_install
helm_lint_aspect = _helm_lint_aspect
helm_lint_test = _helm_lint_test
helm_oci_digest = _helm_oci_digest
helm_package = _helm_package
helm_plugin = _helm_plugin
helm_push = _helm_push
helm_push_images = _helm_push_images
helm_push_registry = _helm_push_registry
helm_template = _helm_template
helm_template_test = _helm_template_test
helm_toolchain = _helm_toolchain
helm_uninstall = _helm_uninstall
helm_upgrade = _helm_upgrade
HelmImageInfo = _HelmImageInfo
HelmOCIDigestInfo = _HelmOCIDigestInfo
HelmPackageInfo = _HelmPackageInfo

image_push = _image_push

helm_img_image = _helm_img_image
helm_oci_manifest = _helm_oci_manifest

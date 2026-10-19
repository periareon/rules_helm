"""# rules_img integration.

Rules that build on [rules_img](https://github.com/bazel-contrib/rules_img).
"""

load("@rules_img//img:image.bzl", "image_manifest")
load("@rules_img//img:layer.bzl", "layer_from_file")
load("@rules_img//img:push.bzl", "image_push_spec")
load("//helm/private:oci_parts.bzl", "helm_oci_parts")

_HELM_CHART_MEDIA_TYPE = "application/vnd.cncf.helm.chart.content.v1.tar+gzip"
_HELM_CONFIG_MEDIA_TYPE = "application/vnd.cncf.helm.config.v1+json"

def helm_oci_manifest(
        *,
        name,
        chart,
        registry_url = None,
        registry_url_file = None,
        visibility = None,
        **kwargs):
    """Describe a chart as the OCI artifact `helm push` creates, for `rules_img`'s `multi_deploy`.

    The target is an `image_manifest` that provides `DeployInfo`, so it can be listed in the
    `operations` of a [`multi_deploy`](https://github.com/bazel-contrib/rules_img). Running the
    `multi_deploy` pushes the chart to `<registry_url>/<chart name>:<chart version>`, as
    `helm push` would. Only the chart is pushed; push its images with their own targets.

    ```python
    load("@rules_helm//helm:rules_img.bzl", "helm_oci_manifest")
    load("@rules_img//img:multi_deploy.bzl", "multi_deploy")

    helm_oci_manifest(
        name = "my_chart_oci_manifest",
        chart = ":my_chart",
        registry_url = "oci://registry.example.com/charts",
    )

    multi_deploy(
        name = "deploy",
        operations = [":my_chart_oci_manifest"],
    )
    ```

    The pushed manifest has the same config, layer and annotations as `helm push`, but a
    different digest from the one `helm push` and [helm_oci_digest](./helm_oci_digest.md#helm_oci_digest) give,
    because `rules_img` adds a top-level `mediaType` field to the manifest. To pin a chart pushed
    this way by digest, use the `digest` output group of `{name}`, not `{chart}.oci_digest`. Do
    not push the same chart version with both `helm_oci_manifest` and `helm_push` to a registry with
    immutable tags. The digests can match once `rules_img` can leave the field out and
    `helm_oci_manifest` uses that option.

    Compared with [helm_push](./helm_push.md#helm_push):
    - Only `oci://` registries are supported, so `push_cmd` and plugins such as `cm-push` are not.
    - Registry credentials come from `rules_img` (Docker config and credential helpers), not from
      `HELM_REGISTRY_USERNAME` and `HELM_REGISTRY_PASSWORD`.
    - There is no `include_images`.

    `rules_img` expands Go templates in annotation values. `{{` in a chart's metadata is escaped,
    so the annotations match the chart.

    | target | rule |
    | --- | --- |
    | `{name}` | `image_manifest` |
    | `{name}.oci_parts` | config blob, annotations, tag, destination and layer files |
    | `{name}.layer` | `layer_from_file` |
    | `{name}.push_spec` | `image_push_spec` |

    Args:
        name (str): The name of the `image_manifest` target.
        chart (Label): A [helm_chart](./helm_chart.md#helm_chart) or [helm_package](./helm_package.md#helm_package)
            target. Charts from [helm_import](./helm_import.md#helm_import) are not supported.
        registry_url (str, optional): The registry URL given to `helm push`, for example
            `oci://registry.example.com/charts`. Mutually exclusive with `registry_url_file`.
        registry_url_file (Label, optional): A file containing the registry URL. Mutually
            exclusive with `registry_url`.
        visibility (list, optional): The visibility of `{name}`. The other targets are private.
        **kwargs (dict): Common attributes such as `tags`, `target_compatible_with` and
            `testonly`, applied to every target.
    """
    helm_oci_parts(
        name = name + ".oci_parts",
        chart = chart,
        registry_url = registry_url,
        registry_url_file = registry_url_file,
        annotations_out = name + ".oci_parts.annotations.json",
        chart_out = name + ".oci_parts.tgz",
        config_out = name + ".oci_parts.config.json",
        destination_out = name + ".oci_parts.destination.txt",
        tag_out = name + ".oci_parts.tag.txt",
        visibility = ["//visibility:private"],
        **kwargs
    )

    layer_from_file(
        name = name + ".layer",
        src = name + ".oci_parts.tgz",
        media_type = _HELM_CHART_MEDIA_TYPE,
        visibility = ["//visibility:private"],
        **kwargs
    )

    image_push_spec(
        name = name + ".push_spec",
        destination_file = name + ".oci_parts.destination.txt",
        tag_file = name + ".oci_parts.tag.txt",
        visibility = ["//visibility:private"],
        **kwargs
    )

    image_manifest(
        name = name,
        annotations_file = name + ".oci_parts.annotations.json",
        config_fragment = name + ".oci_parts.config.json",
        config_media_type = _HELM_CONFIG_MEDIA_TYPE,
        layers = [name + ".layer"],
        push_specs = [name + ".push_spec"],
        # A SOCI index would add an annotation `helm push` does not write.
        soci = "disabled",
        visibility = visibility,
        **kwargs
    )

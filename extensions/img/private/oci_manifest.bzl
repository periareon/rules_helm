"""`helm_oci_manifest`, which describes a chart to `rules_img` as the OCI artifact `helm push` creates."""

load("@rules_helm//helm:defs.bzl", "HelmPackageInfo")
load("@rules_img//img:image.bzl", "image_manifest")
load("@rules_img//img:layer.bzl", "layer_from_file")
load("@rules_img//img:push.bzl", "image_push_spec")

_HELM_CHART_MEDIA_TYPE = "application/vnd.cncf.helm.chart.content.v1.tar+gzip"
_HELM_CONFIG_MEDIA_TYPE = "application/vnd.cncf.helm.config.v1+json"

def _helm_oci_parts_impl(ctx):
    if ctx.attr.registry_url and ctx.attr.registry_url_file:
        fail("`registry_url` and `registry_url_file` are mutually exclusive. Only one may be specified for target `{}`.".format(ctx.label))
    if not ctx.attr.registry_url and not ctx.attr.registry_url_file:
        fail("Either `registry_url` or `registry_url_file` must be specified for target `{}`.".format(ctx.label))

    pkg_info = ctx.attr.chart[HelmPackageInfo]
    inputs = [pkg_info.chart, pkg_info.metadata]
    outputs = [
        ctx.outputs.config_out,
        ctx.outputs.annotations_out,
        ctx.outputs.tag_out,
        ctx.outputs.destination_out,
    ]

    args = ctx.actions.args()
    args.add("-chart", pkg_info.chart)
    args.add("-metadata", pkg_info.metadata)
    if ctx.attr.registry_url:
        args.add("-registry_url", ctx.attr.registry_url)
    else:
        args.add("-registry_url_file", ctx.file.registry_url_file)
        inputs.append(ctx.file.registry_url_file)
    args.add("-config_output", ctx.outputs.config_out)
    args.add("-annotations_output", ctx.outputs.annotations_out)
    args.add("-tag_output", ctx.outputs.tag_out)
    args.add("-destination_output", ctx.outputs.destination_out)

    ctx.actions.run(
        executable = ctx.executable._oci_parts_tool,
        arguments = [args],
        inputs = inputs,
        outputs = outputs,
        mnemonic = "HelmOCIParts",
        progress_message = "Computing OCI artifact parts for %s" % ctx.label,
    )

    # The layer must be the same .tgz the other parts were read from, which is
    # not always the chart target's default output.
    ctx.actions.symlink(
        output = ctx.outputs.chart_out,
        target_file = pkg_info.chart,
    )

    return [DefaultInfo(files = depset(outputs + [ctx.outputs.chart_out]))]

_helm_oci_parts = rule(
    implementation = _helm_oci_parts_impl,
    doc = "Write the config blob, annotations, tag, destination and layer of the OCI artifact `helm push` creates for a chart.",
    attrs = {
        "annotations_out": attr.output(
            doc = "The manifest annotations, as a JSON object.",
            mandatory = True,
        ),
        "chart": attr.label(
            doc = "A helm_chart target providing HelmPackageInfo.",
            providers = [HelmPackageInfo],
            mandatory = True,
        ),
        "chart_out": attr.output(
            doc = "The chart .tgz, which is the only layer.",
            mandatory = True,
        ),
        "config_out": attr.output(
            doc = "The config blob.",
            mandatory = True,
        ),
        "destination_out": attr.output(
            doc = "`<registry>/<repository>`.",
            mandatory = True,
        ),
        "registry_url": attr.string(
            doc = "The registry URL given to `helm push`. Mutually exclusive with `registry_url_file`.",
        ),
        "registry_url_file": attr.label(
            doc = "A file containing the registry URL given to `helm push`. Mutually exclusive with `registry_url`.",
            allow_single_file = True,
        ),
        "tag_out": attr.output(
            doc = "The tag.",
            mandatory = True,
        ),
        "_oci_parts_tool": attr.label(
            executable = True,
            cfg = "exec",
            default = Label("@rules_helm//helm/private/oci_parts"),
        ),
    },
)

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
    `multi_deploy` pushes the chart to `<registry_url>/<chart name>:<chart version>`, with `+`
    in the version replaced by `_`, as `helm push` would. Only the chart is pushed; push its
    images with their own targets.

    ```python
    load("@rules_helm_img//:defs.bzl", "helm_oci_manifest")
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

    The pushed manifest is the one `helm push` creates when it runs in UTC, so its digest is the
    one [helm_oci_digest](./helm_oci_digest.md#helm_oci_digest) gives. Helm writes the
    `org.opencontainers.image.created` annotation in the local time zone, so `helm push` in
    another zone pushes a different digest for the same chart.

    Compared with [helm_push](./helm_push.md#helm_push):
    - Only `oci://` registries are supported, so `push_cmd` and plugins such as `cm-push` are not.
    - Registry credentials come from `rules_img` (Docker config and credential helpers), not from
      the `HELM_REGISTRY_*` variables (`HELM_REGISTRY_USERNAME`, `HELM_REGISTRY_PASSWORD` and
      `HELM_REGISTRY_PASSWORD_FILE`).
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
    _helm_oci_parts(
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
        # `helm push` writes no top-level `mediaType`.
        omit_media_type = True,
        # A chart has no platform. Without this, the descriptor records the build host's.
        omit_platform = True,
        # A SOCI index would add an annotation `helm push` does not write.
        soci = "disabled",
        visibility = visibility,
        **kwargs
    )

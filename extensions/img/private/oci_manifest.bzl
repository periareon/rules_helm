"""`helm_oci_manifest`, which describes a chart to `rules_img` as the OCI artifact `helm push` creates."""

load("@rules_helm//helm:defs.bzl", "HelmOCIDigestInfo", "HelmPackageInfo", "helm_oci_digest")
load("@rules_img//img:image.bzl", "image_manifest")
load("@rules_img//img:layer.bzl", "layer_from_file")
load("@rules_img//img:push.bzl", "image_push_spec")

_HELM_CHART_MEDIA_TYPE = "application/vnd.cncf.helm.chart.content.v1.tar+gzip"
_HELM_CONFIG_MEDIA_TYPE = "application/vnd.cncf.helm.config.v1+json"

# `rules_img` expands Go templates in each `annotations_file` value, but not in
# the keys. This writes the annotations back as a JSON object with every `{{`
# in a value replaced by `{{"{{"}}`, which expands back to `{{`.
_ESCAPE_ANNOTATIONS = "".join([
    '{{ "{" }}{{ $sep := "" }}{{ range $k, $v := . }}{{ $sep }}',
    r'{{ toJson $k }}:{{ $v | replace "{{" "{{\"{{\"}}" | toJson }}',
    '{{ $sep = "," }}{{ end }}{{ "}" }}',
])

def _helm_oci_manifest_files_impl(ctx):
    digest_info = ctx.attr.digest[HelmOCIDigestInfo]
    if not digest_info.repository:
        fail("`helm_oci_manifest` `{}` needs `registry_url` or `registry_url_file`.".format(
            ctx.label.name.removesuffix(".files"),
        ))

    args = ctx.actions.args()
    args.add("-input", digest_info.annotations)
    args.add("-output", ctx.outputs.annotations_out)
    args.add("-template", _ESCAPE_ANNOTATIONS)
    ctx.actions.run(
        executable = ctx.executable._json_extractor,
        arguments = [args],
        inputs = [digest_info.annotations],
        outputs = [ctx.outputs.annotations_out],
        mnemonic = "HelmOCIAnnotations",
        progress_message = "Escaping OCI annotations for %s" % ctx.label,
    )

    # The layer is the .tgz from `HelmPackageInfo`, the one the digest was
    # computed over, which is not always the chart target's default output.
    for output, target_file in [
        (ctx.outputs.chart_out, ctx.attr.digest[HelmPackageInfo].chart),
        (ctx.outputs.config_out, digest_info.config),
        (ctx.outputs.repository_out, digest_info.repository),
        (ctx.outputs.tag_out, digest_info.tag),
    ]:
        ctx.actions.symlink(output = output, target_file = target_file)

    return [DefaultInfo(files = depset([
        ctx.outputs.annotations_out,
        ctx.outputs.chart_out,
        ctx.outputs.config_out,
        ctx.outputs.repository_out,
        ctx.outputs.tag_out,
    ]))]

_helm_oci_manifest_files = rule(
    implementation = _helm_oci_manifest_files_impl,
    doc = "Hand the files of a `helm_oci_digest` target to `rules_img`, with the annotations escaped for its template expansion.",
    attrs = {
        "annotations_out": attr.output(
            doc = "The manifest annotations, as a JSON object, escaped for `rules_img`.",
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
        "digest": attr.label(
            doc = "A `helm_oci_digest` target with a registry URL.",
            providers = [HelmOCIDigestInfo, HelmPackageInfo],
            mandatory = True,
        ),
        "repository_out": attr.output(
            doc = "`<registry>/<repository>`.",
            mandatory = True,
        ),
        "tag_out": attr.output(
            doc = "The tag.",
            mandatory = True,
        ),
        "_json_extractor": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("@rules_helm//helm/private/json_extractor"),
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
    | `{name}.oci_digest` | [helm_oci_digest](./helm_oci_digest.md#helm_oci_digest) |
    | `{name}.files` | config blob, annotations, tag, repository and layer files |
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

    # A `select()` is only resolved at analysis, where `helm_oci_digest` and
    # `_helm_oci_manifest_files` check it.
    if type(registry_url) != "select" and type(registry_url_file) != "select":
        if registry_url and registry_url_file:
            fail("`helm_oci_manifest` `{}` takes `registry_url` or `registry_url_file`, not both.".format(name))
        if not registry_url and not registry_url_file:
            fail("`helm_oci_manifest` `{}` needs `registry_url` or `registry_url_file`.".format(name))

    helm_oci_digest(
        name = name + ".oci_digest",
        chart = chart,
        registry_url = registry_url,
        registry_url_file = registry_url_file,
        visibility = ["//visibility:private"],
        **kwargs
    )

    _helm_oci_manifest_files(
        name = name + ".files",
        digest = name + ".oci_digest",
        annotations_out = name + ".files.annotations.json",
        chart_out = name + ".files.tgz",
        config_out = name + ".files.config.json",
        repository_out = name + ".files.repository.txt",
        tag_out = name + ".files.tag.txt",
        visibility = ["//visibility:private"],
        **kwargs
    )

    layer_from_file(
        name = name + ".layer",
        src = name + ".files.tgz",
        media_type = _HELM_CHART_MEDIA_TYPE,
        visibility = ["//visibility:private"],
        **kwargs
    )

    image_push_spec(
        name = name + ".push_spec",
        destination_file = name + ".files.repository.txt",
        tag_file = name + ".files.tag.txt",
        visibility = ["//visibility:private"],
        **kwargs
    )

    image_manifest(
        name = name,
        annotations_file = name + ".files.annotations.json",
        config_fragment = name + ".files.config.json",
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

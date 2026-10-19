"""The parts of the OCI artifact `helm push` creates, as files for `rules_img`."""

load(":providers.bzl", "HelmPackageInfo")

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

helm_oci_parts = rule(
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
            default = Label("//helm/private/oci_parts"),
        ),
    },
)

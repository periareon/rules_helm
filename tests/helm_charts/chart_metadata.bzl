"""Exposes the metadata that `helm_import` records for a chart."""

load("//helm:defs.bzl", "HelmPackageInfo")

def _chart_metadata_impl(ctx):
    return [DefaultInfo(files = depset([ctx.attr.chart[HelmPackageInfo].metadata]))]

chart_metadata = rule(
    implementation = _chart_metadata_impl,
    doc = "The `name` and `version` that a `helm_import` target records, as a JSON file.",
    attrs = {
        "chart": attr.label(
            doc = "A `helm_import` target, or an alias of one.",
            mandatory = True,
            providers = [HelmPackageInfo],
        ),
    },
)

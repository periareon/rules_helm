"""Helm rules for managing external dependencies"""

load(":chart_utils.bzl", "chart_utils")
load(":import_authn.bzl", "authn")
load(":oci_chart.bzl", "oci_chart")
load(":providers.bzl", "HelmPackageInfo")

def _helm_import_impl(ctx):
    metadata_output = ctx.actions.declare_file(ctx.label.name + ".metadata.json")
    ctx.actions.write(
        output = metadata_output,
        content = json.encode_indent(struct(
            name = ctx.label.name,
            version = ctx.attr.version,
        ), indent = " " * 4),
    )

    return [
        DefaultInfo(
            files = depset([ctx.file.chart]),
            runfiles = ctx.runfiles([ctx.file.chart]),
        ),
        HelmPackageInfo(
            chart = ctx.file.chart,
            images = [],
            metadata = metadata_output,
        ),
    ]

helm_import = rule(
    implementation = _helm_import_impl,
    doc = "A rule that allows pre-packaged Helm charts to be used within Bazel.",
    attrs = {
        "chart": attr.label(
            doc = "A Helm chart's `.tgz` file.",
            allow_single_file = [".tgz"],
        ),
        "version": attr.string(
            doc = "The version fo the helm chart",
        ),
    },
)

def _find_chart_url(repository_ctx, repo_file, chart_name, chart_version):
    # HTTP source for `repository_ctx.download`:
    chart_file = "{}-{}.tgz".format(chart_name, chart_version)

    # OCI source:
    oci_identifier = "{}:{}".format(chart_name, chart_version)

    repo_def = repository_ctx.read(repo_file)
    lines = repo_def.splitlines()
    for line in lines:
        line = line.lstrip(" ")
        if line.startswith("-") and line.endswith(chart_file) or line.endswith(oci_identifier):
            url = line.lstrip("-").lstrip(" ")
            if url.startswith("http") and url.endswith("/{}".format(chart_file)):
                return url
            if url.startswith("oci") and url.endswith("/{}".format(oci_identifier)):
                return url
            if not url.startswith("http") and not url.startswith("oci"):
                return "{}/{}".format(repository_ctx.attr.repository, url)
    fail("cannot find {} (version {}) in {}".format(chart_name, chart_version, repository_ctx.attr.repository))

def _get_chart_name_and_version(chart_url, chart_file):
    if chart_url.startswith("oci"):
        # The url names the chart and the version exactly.
        chart_name, chart_version = chart_url.split("/")[-1].split(":")
        return chart_name, chart_version
    return chart_utils.split_chart_file(chart_file)

def _get_chart_file_name(chart_url):
    if chart_url.startswith("http") and chart_url.endswith(".tgz"):
        return chart_url.split("/")[-1]
    if chart_url.startswith("oci"):
        chart_name, chart_version = chart_url.split("/")[-1].split(":")
        return "{}-{}.tgz".format(chart_name, chart_version)
    fail("cannot determine chart file name from {}".format(chart_url))

_HELM_DEP_BUILD_FILE = """\
load("@rules_helm//helm:defs.bzl", "helm_import")

helm_import(
    name = "{chart_name}",
    chart = "{chart_file}",
    visibility = ["//visibility:public"],
)

alias(
    name = "{repository_name}",
    actual = ":{chart_name}",
    visibility = ["//visibility:public"],
)
"""

def _helm_import_repository_impl(repository_ctx):
    if repository_ctx.attr.url and repository_ctx.attr.repository:
        fail("`url` and `repository` are exclusive arguments.")

    if repository_ctx.attr.url:
        chart_url = repository_ctx.attr.url
        if repository_ctx.attr.chart_name:
            fail("`url` provided, do not set `chart_name`")
        if repository_ctx.attr.version:
            fail("`url` provided, do not set `version`")
    else:
        if not repository_ctx.attr.chart_name:
            fail("`chart_name` is required to locate chart")
        if not repository_ctx.attr.version:
            fail("`version` is required to locate chart")

        repo_yaml = "index.yaml"
        repository_ctx.download(
            output = repo_yaml,
            url = "{}/{}".format(
                repository_ctx.attr.repository,
                repo_yaml,
            ),
        )

        chart_url = _find_chart_url(repository_ctx, repo_yaml, repository_ctx.attr.chart_name, repository_ctx.attr.version)

    chart_file = _get_chart_file_name(chart_url)

    if chart_url.startswith("http"):
        result = repository_ctx.download(
            output = repository_ctx.path(chart_file),
            url = chart_url,
            sha256 = repository_ctx.attr.sha256,
        )
    elif chart_url.startswith("oci"):
        chart = oci_chart.parse_url(chart_url)

        # A Helm chart's OCI layer is the chart .tgz, so `sha256` names its
        # blob, and a cached blob needs neither a token nor the manifest.
        result = None
        if repository_ctx.attr.sha256:
            result = repository_ctx.download(
                output = repository_ctx.path(chart_file),
                url = oci_chart.blob_url(chart, "sha256:" + repository_ctx.attr.sha256),
                sha256 = repository_ctx.attr.sha256,
                allow_fail = True,
            )

        if not result or not result.success:
            au = authn.new(repository_ctx)
            layer = oci_chart.find_chart_layer(repository_ctx, au, chart_url)
            chart_blob_url = oci_chart.blob_url(chart, layer.digest)

            # Download the chart package:
            result = repository_ctx.download(
                output = repository_ctx.path(chart_file),
                url = chart_blob_url,
                sha256 = repository_ctx.attr.sha256,
                auth = {
                    chart_blob_url: layer.token,
                },
            )

    else:
        fail("cannot download {} from {}, unsupported scheme".format(repository_ctx.attr.chart_name, chart_url))

    chart_name, chart_version = _get_chart_name_and_version(chart_url, chart_file)

    repository_ctx.file("BUILD.bazel", content = _HELM_DEP_BUILD_FILE.format(
        chart_name = chart_name,
        chart_file = chart_file,
        repository_name = repository_ctx.name,
    ))

    if repository_ctx.attr.url:
        attrs_for_reproducibility = {
            "name": repository_ctx.name,
            "sha256": result.sha256,
            "url": chart_url,
        }
    else:
        attrs_for_reproducibility = {
            "chart_name": chart_name,
            "name": repository_ctx.name,
            "repository": repository_ctx.attr.repository,
            "sha256": result.sha256,
            "version": chart_version,
        }

    # Bazel <8.3.0 lacks repository_ctx.repo_metadata
    if not hasattr(repository_ctx, "repo_metadata"):
        return attrs_for_reproducibility

    reproducible = repository_ctx.attr.sha256 != ""
    return repository_ctx.repo_metadata(
        reproducible = reproducible,
        attrs_for_reproducibility = {} if reproducible else attrs_for_reproducibility,
    )

helm_import_repository = repository_rule(
    implementation = _helm_import_repository_impl,
    doc = "A rule for fetching external Helm charts from an arbitrary URL or repository. With bzlmod, the `helm_charts` extension in `@rules_helm//helm:extensions.bzl` fetches `oci://` charts with this rule and stores the digest it looks up in `MODULE.bazel.lock`.",
    attrs = {
        "chart_name": attr.string(
            doc = "Chart name to import. Must be set if `repository` is specified",
        ),
        "repository": attr.string(
            doc = "Chart repository url where to locate the requested chart. Mutually exclusive with `url`.",
        ),
        "sha256": attr.string(
            doc = "The expected SHA-256 hash of the chart imported. For an `oci://` url, a chart already in the repository cache is then fetched without any request to the registry.",
        ),
        "url": attr.string(
            doc = "The url where a chart can be directly downloaded. Mutually exclusive with `chart_name`, `repository`, and `version`",
        ),
        "version": attr.string(
            doc = "Specify a version constraint for the chart version to use. Must be set if `repository` is specified.",
        ),
    },
)

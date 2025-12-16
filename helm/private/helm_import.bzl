"""Helm rules for managing external dependencies"""

load(":helm_import_authn.bzl", "authn")
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
            if url == chart_file:
                return "{}/{}".format(repository_ctx.attr.repository, url)
            if url.startswith("http") and url.endswith("/{}".format(chart_file)):
                return url
            if url.startswith("oci") and url.endswith("/{}".format(oci_identifier)):
                return url
    fail("cannot find {} (version {}) in {}".format(chart_name, chart_version, repository_ctx.attr.repository))

def _get_chart_file_name(chart_url):
    if chart_url.startswith("http") and chart_url.endswith(".tgz"):
        return chart_url.split("/")[-1]
    if chart_url.startswith("oci"):
        chart_name, chart_version = chart_url.split("/")[-1].split(":")
        return "{}-{}.tgz".format(chart_name, chart_version)
    fail("cannot determine chart file name from {}".format(chart_url))

def _find_chart_digest(manifest):
    for layer in manifest["layers"]:
        # https://helm.sh/docs/topics/registries/#helm-chart-manifest
        if layer["mediaType"] == "application/vnd.cncf.helm.chart.content.v1.tar+gzip":
            return layer["digest"]
    fail("could not find chart content layer")

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
        url, _, chart_version = chart_url.rpartition(":")
        hostname, _, chart_path = url.removeprefix("oci://").partition("/")

        au = authn.new(repository_ctx)
        token = au.get_token(hostname, chart_path)

        # Find the digest for the layer with the chart package in the image manifest:
        manifest_json = "manifest.json"
        manifest_url = "https://{}/v2/{}/manifests/{}".format(
            hostname,
            chart_path,
            chart_version,
        )
        repository_ctx.download(
            output = manifest_json,
            url = manifest_url,
            auth = {
                manifest_url: token,
            },
            # Copied from `helm pull --debug`
            headers = {
                "Accept": [
                    "application/vnd.docker.distribution.manifest.v2+json",
                    "application/vnd.docker.distribution.manifest.list.v2+json",
                    "application/vnd.oci.image.manifest.v1+json",
                    "application/vnd.oci.image.index.v1+json",
                    "*/*",
                ],
            },
        )
        manifest = json.decode(repository_ctx.read(manifest_json))

        # https://helm.sh/docs/topics/registries/#helm-chart-manifest
        if manifest["config"]["mediaType"] != "application/vnd.cncf.helm.config.v1+json":
            fail("{} is not a Helm chart package".format(chart_url))

        chart_digest = _find_chart_digest(manifest)
        chart_blob_url = "https://{}/v2/{}/blobs/{}".format(
            hostname,
            chart_path,
            chart_digest,
        )

        # Download the chart package:
        result = repository_ctx.download(
            output = repository_ctx.path(chart_file),
            url = chart_blob_url,
            sha256 = repository_ctx.attr.sha256,
            auth = {
                chart_blob_url: token,
            },
        )

    else:
        fail("cannot download {} from {}, unsupported scheme".format(repository_ctx.attr.chart_name, chart_url))

    chart_name, _, chart_version = chart_file.removesuffix(".tgz").rpartition("-")

    repository_ctx.file("BUILD.bazel", content = _HELM_DEP_BUILD_FILE.format(
        chart_name = chart_name,
        chart_file = chart_file,
        repository_name = repository_ctx.name,
    ))

    return {
        "chart_name": chart_name,
        "name": repository_ctx.name,
        "repository": repository_ctx.attr.repository,
        "sha256": result.sha256,
        "url": chart_url,
        "version": chart_version,
    }

helm_import_repository = repository_rule(
    implementation = _helm_import_repository_impl,
    doc = "A rule for fetching external Helm charts from an arbitrary URL or repository.",
    attrs = {
        "chart_name": attr.string(
            doc = "Chart name to import. Must be set if `repository` is specified",
        ),
        "repository": attr.string(
            doc = "Chart repository url where to locate the requested chart. Mutually exclusive with `url`.",
        ),
        "sha256": attr.string(
            doc = "The expected SHA-256 hash of the chart imported.",
        ),
        "url": attr.string(
            doc = "The url where a chart can be directly downloaded. Mutually exclusive with `chart_name`, `repository`, and `version`",
        ),
        "version": attr.string(
            doc = "Specify a version constraint for the chart version to use. Must be set if `repository` is specified.",
        ),
    },
)

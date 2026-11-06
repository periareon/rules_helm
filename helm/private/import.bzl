"""Helm rules for managing external dependencies"""

load("@bazel_skylib//lib:versions.bzl", "versions")
load("@package_metadata//purl:purl.bzl", "purl")
load("@package_metadata//rules:package_metadata.bzl", "package_metadata")
load(":import_authn.bzl", "authn")
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
    provides = [HelmPackageInfo],
)

def helm_import_package_metadata(name, chart_name, version, repository, **kwargs):
    """Declares the [`package_metadata`](https://github.com/bazel-contrib/supply-chain/tree/main/metadata) of an imported Helm chart.

    The chart is identified by an `oci` [purl](https://github.com/package-url/purl-spec) carrying
    the chart repository and version as `repository_url` and `tag` qualifiers.

    Args:
        name (str): The name of the target.
        chart_name (str): The name of the chart.
        version (str): The version of the chart.
        repository (str): The chart repository or OCI registry path the chart was fetched from.
        **kwargs (dict): Additional keyword arguments for `package_metadata`.
    """
    package_metadata(
        name = name,
        purl = purl.builder()
            .type("oci")
            .name(chart_name)
            .add_qualifier("repository_url", repository)
            .add_qualifier("tag", version)
            .build(),
        **kwargs
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
load("@rules_helm//helm:defs.bzl", "helm_import", "helm_import_package_metadata")

helm_import_package_metadata(
    name = "package_metadata",
    chart_name = "{chart_name}",
    repository = "{repository_url}",
    version = "{chart_version}",
    visibility = ["//visibility:public"],
)

helm_import(
    name = "{chart_name}",
    chart = "{chart_file}",
    {package_metadata_attr} = [":package_metadata"],
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

        # A Helm chart's OCI layer is the chart .tgz, so `sha256` names its
        # blob, and a cached blob needs neither a token nor the manifest.
        result = None
        if repository_ctx.attr.sha256:
            result = repository_ctx.download(
                output = repository_ctx.path(chart_file),
                url = "https://{}/v2/{}/blobs/sha256:{}".format(
                    hostname,
                    chart_path,
                    repository_ctx.attr.sha256,
                ),
                sha256 = repository_ctx.attr.sha256,
                allow_fail = True,
            )

        if not result or not result.success:
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
            if manifest.get("config", {}).get("mediaType") != "application/vnd.cncf.helm.config.v1+json":
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

    if repository_ctx.attr.url:
        # The chart's parent path, e.g. `oci://registry-1.docker.io/bitnamicharts`.
        repository_url = chart_url.rpartition("/")[0]
    else:
        repository_url = repository_ctx.attr.repository

    # Bazel 8.0.0 renamed the `applicable_licenses` common attribute to `package_metadata`.
    package_metadata_attr = "applicable_licenses"
    if not native.bazel_version or versions.is_at_least("8.0.0", native.bazel_version):
        package_metadata_attr = "package_metadata"

    repository_ctx.file("BUILD.bazel", content = _HELM_DEP_BUILD_FILE.format(
        chart_name = chart_name,
        chart_file = chart_file,
        chart_version = chart_version,
        package_metadata_attr = package_metadata_attr,
        repository_name = repository_ctx.name,
        repository_url = repository_url.rstrip("/"),
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
    doc = "A rule for fetching external Helm charts from an arbitrary URL or repository.",
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

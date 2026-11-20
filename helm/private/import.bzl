"""Helm rules for managing external dependencies"""

load("@package_metadata//purl:purl.bzl", "purl")
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
    provides = [HelmPackageInfo],
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

def _get_chart_file_name(chart_url, oci):
    if chart_url.startswith("http") and chart_url.endswith(".tgz"):
        return chart_url.split("/")[-1]
    if oci:
        return "{}-{}.tgz".format(oci.name, oci.version)
    fail("cannot determine chart file name from {}".format(chart_url))

def _chart_purl(chart_url, oci, chart_name, chart_version, sha256):
    """Builds the [purl](https://github.com/package-url/purl-spec) identifying an imported chart.

    Args:
        chart_url (str): The `https://` or `oci://` url the chart was fetched from.
        oci (struct): The chart from `oci_chart.parse_url` for an `oci://` url, otherwise `None`.
            An `oci://` chart is identified by this alone, so `chart_name`, `chart_version`
            and `sha256` are not used for it.
        chart_name (str): The name of the chart, from its `Chart.yaml`.
        chart_version (str): The version of the chart, from its `Chart.yaml`.
        sha256 (str): The sha256 of the chart `.tgz`.

    Returns:
        str: A `pkg:oci/...` purl for a chart from an OCI registry, `pkg:generic/...` otherwise.
    """
    if oci:
        # https://github.com/package-url/purl-spec/blob/main/types/oci-definition.json
        # The version of an `oci` purl is the manifest digest, which a chart
        # served from the repository cache never fetches, so the chart is
        # identified by its tag alone. The tag is taken from the url: an OCI
        # tag cannot hold the `+` of a chart version, so it can differ from
        # the version in `Chart.yaml`.
        return (purl.builder()
            .type("oci")
            .name(oci.name)
            .add_qualifier("repository_url", "{}/{}".format(oci.hostname, oci.path))
            .add_qualifier("tag", oci.version)
            .build())

    # https://github.com/package-url/purl-spec/blob/main/types/generic-definition.json
    return (purl.builder()
        .type("generic")
        .name(chart_name)
        .version(chart_version)
        .add_qualifier("download_url", chart_url)
        .add_qualifier("checksum", "sha256:" + sha256)
        .build())

# File names under which charts ship their license text, by preference.
_LICENSE_FILES = ["LICENSE", "LICENSE.txt", "LICENSE.md", "LICENCE", "COPYING"]

# `Chart.yaml` annotations naming the chart's SPDX license identifier, by
# preference. `licenses` is used by bitnami, the other by Artifact Hub.
_LICENSE_ANNOTATIONS = ["licenses", "artifacthub.io/license"]

# Distinctive phrases of common license texts, for charts shipping a license
# file without naming it in `Chart.yaml`. Every phrase must appear. Order
# matters where one text contains another (BSD-3-Clause before BSD-2-Clause).
# The GPL family is left out: the text does not say `-only` or `-or-later`.
_LICENSE_TEXT_MARKERS = [
    (["Apache License", "Version 2.0"], "Apache-2.0"),
    (["Mozilla Public License", "2.0"], "MPL-2.0"),
    (["Permission is hereby granted, free of charge"], "MIT"),
    (["Redistribution and use in source and binary forms", "Neither the name"], "BSD-3-Clause"),
    (["Redistribution and use in source and binary forms"], "BSD-2-Clause"),
    (["Permission to use, copy, modify, and/or distribute this software"], "ISC"),
    (["This is free and unencumbered software released into the public domain"], "Unlicense"),
]

_SPDX_LICENSE_KINDS = Label("@package_metadata//licenses/spdx:BUILD")

def _spdx_identifiers(repository_ctx):
    """The SPDX identifiers `@package_metadata` declares a `license_kind` for."""
    identifiers = {}
    for line in repository_ctx.read(_SPDX_LICENSE_KINDS).splitlines():
        line = line.strip()
        if line.startswith("identifier = "):
            identifiers[chart_utils.scalar(line.removeprefix("identifier = ").rstrip(","))] = None
    return identifiers

def _chart_license(repository_ctx, chart_dir, annotations):
    """Determines the license of a chart from its `Chart.yaml` and license file.

    Args:
        repository_ctx (repository_ctx): The repository context.
        chart_dir (path): The extracted chart.
        annotations (dict): The `annotations` of the chart's `Chart.yaml`.

    Returns:
        tuple: The SPDX identifier of the license and the name of the license
            file in the chart, either of which is `None` when unknown. The
            identifier is one `@package_metadata` has a `license_kind` for.
    """
    text = None
    for name in _LICENSE_FILES:
        if chart_dir.get_child(name).exists:
            text = name
            break

    identifier = None
    for annotation in _LICENSE_ANNOTATIONS:
        if annotations.get(annotation):
            identifier = annotations[annotation]
            break

    if not identifier and text:
        content = repository_ctx.read(chart_dir.get_child(text))
        for markers, candidate in _LICENSE_TEXT_MARKERS:
            if all([marker in content for marker in markers]):
                identifier = candidate
                break

    # A license expression (`MIT OR Apache-2.0`) or an unknown identifier has
    # no `license_kind` to point at.
    if identifier and identifier not in _spdx_identifiers(repository_ctx):
        identifier = None

    return identifier, text

_NOASSERTION = Label("//helm/private:noassertion")

_HELM_DEP_REPO_FILE = """\
repo(default_package_metadata = ["//:package_metadata"])
"""

_HELM_DEP_BUILD_FILE = """\
load("@rules_helm//helm:defs.bzl", "helm_import")
load("@rules_helm//helm/private:package_metadata.bzl", "license", "package_metadata")

package_metadata(
    name = "package_metadata",
    attributes = [":license"],
    purl = "{purl}",
    visibility = ["//visibility:public"],
)

license(
    name = "license",
    kind = "{kind}",{text}
    visibility = ["//visibility:public"],
)

helm_import(
    name = "{chart_name}",
    chart = "{chart_file}",
    version = "{chart_version}",
    visibility = ["//visibility:public"],
)
{alias}"""

# Makes `@<repository name>` resolve to the chart. Left out when the chart has
# the name of the repository, because the `helm_import` target is then already
# the default target, and a second target with that name is an error.
_HELM_DEP_ALIAS = """
alias(
    name = "{repository_name}",
    actual = ":{chart_name}",
    visibility = ["//visibility:public"],
)
"""

# Targets that the generated `BUILD.bazel` always declares.
_RESERVED_TARGETS = ["license", "package_metadata"]

def _generate_build_file(repository_ctx, chart_file, chart_url, oci, sha256):
    """Writes the `BUILD.bazel` and `REPO.bazel` of an imported chart.

    The chart is unpacked to read its `Chart.yaml` and license file, then
    removed again. The license file, if any, is kept at the repository root.
    The name and the version of the chart are those in its `Chart.yaml`.

    Args:
        repository_ctx (repository_ctx): The repository context.
        chart_file (str): The chart `.tgz` in the repository.
        chart_url (str): The `https://` or `oci://` url the chart was fetched from.
        oci (struct): The chart from `oci_chart.parse_url` for an `oci://` url, otherwise `None`.
        sha256 (str): The sha256 of the chart `.tgz`.
    """
    chart_dir = repository_ctx.path("chart")
    repository_ctx.extract(archive = chart_file, output = chart_dir)

    # A chart package holds a single directory named after the chart.
    entries = chart_dir.readdir()
    if len(entries) != 1 or not entries[0].is_dir:
        fail("{} is not a Helm chart package: expected a single chart directory, found {}".format(
            chart_file,
            [entry.basename for entry in entries],
        ))
    chart_root = entries[0]

    chart_yaml = chart_root.get_child("Chart.yaml")
    if not chart_yaml.exists:
        fail("{} is not a Helm chart package: it has no Chart.yaml".format(chart_url))
    fields, annotations = chart_utils.parse_chart_yaml(repository_ctx.read(chart_yaml))

    # The name becomes a target name and the version a string in `BUILD.bazel`.
    chart_name = fields.get("name")
    chart_version = fields.get("version")
    if not chart_utils.is_chart_name(chart_name):
        fail("{} is not a Helm chart package: the `name` in its Chart.yaml is {}, which is not a name of letters, digits, `-`, `.` and `_`".format(chart_url, repr(chart_name)))
    if not chart_utils.is_chart_version(chart_version):
        fail("{} is not a Helm chart package: the `version` in its Chart.yaml is {}, which is not a version of letters, digits, `-`, `.`, `_` and `+`".format(chart_url, repr(chart_version)))

    for name in [chart_name, repository_ctx.original_name]:
        if name in _RESERVED_TARGETS:
            fail("{}: `{}` is the name of a target that the generated BUILD.bazel declares, so it cannot name the chart or the repository".format(chart_url, name))
    identifier, text = _chart_license(repository_ctx, chart_root, annotations)

    kind = _NOASSERTION
    if identifier:
        kind = Label("@package_metadata//licenses/spdx:" + identifier)

    text_attr = ""
    if text:
        repository_ctx.file(text, content = repository_ctx.read(chart_root.get_child(text)), executable = False)
        text_attr = '\n    text = "{}",'.format(text)

    repository_ctx.delete(chart_dir)

    repository_ctx.file("REPO.bazel", content = _HELM_DEP_REPO_FILE)

    # `original_name` is the name given in the `MODULE.bazel` tag or the rule call.
    # `name` is the canonical name, which `@<name>` cannot refer to under bzlmod.
    alias = ""
    if repository_ctx.original_name != chart_name:
        alias = _HELM_DEP_ALIAS.format(
            chart_name = chart_name,
            repository_name = repository_ctx.original_name,
        )

    repository_ctx.file("BUILD.bazel", content = _HELM_DEP_BUILD_FILE.format(
        alias = alias,
        chart_file = chart_file,
        chart_name = chart_name,
        chart_version = chart_version,
        kind = str(kind),
        purl = _chart_purl(chart_url, oci, chart_name, chart_version, sha256),
        text = text_attr,
    ))

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

    oci = None
    if chart_url.startswith("oci"):
        oci = oci_chart.parse_url_or_fail(chart_url)

    chart_file = _get_chart_file_name(chart_url, oci)

    if chart_url.startswith("http"):
        result = repository_ctx.download(
            output = repository_ctx.path(chart_file),
            url = chart_url,
            sha256 = repository_ctx.attr.sha256,
        )
    elif oci:
        # A Helm chart's OCI layer is the chart .tgz, so `sha256` names its
        # blob, and a cached blob needs neither a token nor the manifest.
        result = None
        if repository_ctx.attr.sha256:
            result = repository_ctx.download(
                output = repository_ctx.path(chart_file),
                url = oci_chart.blob_url(oci, "sha256:" + repository_ctx.attr.sha256),
                sha256 = repository_ctx.attr.sha256,
                allow_fail = True,
            )

        if not result or not result.success:
            au = authn.new(repository_ctx)
            layer = oci_chart.find_chart_layer(repository_ctx, au, chart_url)
            chart_blob_url = oci_chart.blob_url(oci, layer.digest)

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

    _generate_build_file(
        repository_ctx,
        chart_file = chart_file,
        chart_url = chart_url,
        oci = oci,
        sha256 = result.sha256,
    )

    if repository_ctx.attr.url:
        attrs_for_reproducibility = {
            "name": repository_ctx.name,
            "sha256": result.sha256,
            "url": chart_url,
        }
    else:
        attrs_for_reproducibility = {
            "chart_name": repository_ctx.attr.chart_name,
            "name": repository_ctx.name,
            "repository": repository_ctx.attr.repository,
            "sha256": result.sha256,
            "version": repository_ctx.attr.version,
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
    doc = """\
A rule for fetching external Helm charts from an arbitrary URL or repository.

With bzlmod, the `helm_charts` extension in `@rules_helm//helm:extensions.bzl` fetches
`oci://` charts with this rule and stores the digest it looks up in `MODULE.bazel.lock`.

The repository exposes the chart as a `helm_import` target. The target takes its name and
`version` from the `Chart.yaml` of the chart, not from the file name or the tag of the url.
A chart fetched from `oci://.../cert-manager:1.19.4` has the version `v1.19.4` if its
`Chart.yaml` says so, and `helm push` uses that version as the tag. The name can use
letters, digits, `-`, `.` and `_`, and the version the same characters and `+`. Neither the
chart name nor the repository name can be `license` or `package_metadata`. The target is
aliased to the repository name, so `@<name>` resolves to it, unless the chart has the same
name as the repository. The repository also describes the chart for supply-chain tooling built on
[package_metadata](https://github.com/bazel-contrib/supply-chain):

- `//:package_metadata` identifies the chart by [purl](https://github.com/package-url/purl-spec),
  `pkg:oci/...` for a chart from an OCI registry and `pkg:generic/...` with the `download_url`
  and sha256 `checksum` otherwise. It is the `default_package_metadata` of the repository.
- `//:license` declares the chart's license, the SPDX identifier named by the `licenses` or
  `artifacthub.io/license` annotation of `Chart.yaml` or recognized in the `LICENSE` file
  shipped with the chart. It is `NOASSERTION` when neither is available. The license file,
  if any, is kept next to the chart as the license text.
""",
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

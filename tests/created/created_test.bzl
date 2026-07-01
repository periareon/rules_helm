"""helm_package derives the OCI `org.opencontainers.image.created` annotation
from the chart's own annotation, canonicalized to RFC3339, defaulting to
reproducible epoch-0 when it is absent or a `{KEY}` stamp token is unresolved.
"""

load("@bazel_skylib//rules:diff_test.bzl", "diff_test")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("//helm:defs.bzl", "helm_chart", "helm_package")
load("//helm:helm_package_info.bzl", "HelmPackageInfo")

def _helm_pkg_metadata_impl(ctx):
    return DefaultInfo(files = depset([ctx.attr.chart[HelmPackageInfo].metadata]))

_helm_pkg_metadata = rule(
    implementation = _helm_pkg_metadata_impl,
    doc = "Extracts the `metadata.json` sidecar from a `helm_package` target.",
    attrs = {
        "chart": attr.label(
            doc = "The `helm_package` target to parse metadata from.",
            providers = [HelmPackageInfo],
            mandatory = True,
        ),
    },
)

def _chart_json(created = None):
    content = {
        "apiVersion": "v2",
        "appVersion": "1.16.0",
        "description": "A Helm chart for testing the created annotation.",
        "icon": "https://helm.sh/img/helm.svg",
        "name": "created",
        "type": "application",
        "version": "0.1.0",
    }
    if created != None:
        content["annotations"] = {"org.opencontainers.image.created": created}
    return json.encode(content)

def _metadata_golden(name, created):
    write_file(
        name = "{}.expected_metadata".format(name),
        out = "{}.expected_metadata.json".format(name),
        content = """\
{{
    "created": "{}",
    "name": "created",
    "version": "0.1.0"
}}
""".format(created).splitlines(),
        newline = "unix",
    )

def created_test_suite(name):
    """Declares the created-annotation test targets.

    Args:
        name: Name for the wrapping test_suite target.
    """

    tests = []

    # variant -> (annotation value, stamp, expected canonical `created`)
    variants = {
        "default.no_stamp": (None, 0, "1970-01-01T00:00:00Z"),
        "default.stamp": (None, 1, "1970-01-01T00:00:00Z"),
        "literal_epoch": ("1751328000", 0, "2025-07-01T00:00:00Z"),
        "literal_rfc3339": ("2026-07-01T00:00:00Z", 0, "2026-07-01T00:00:00Z"),
        "token.no_stamp": ("{STABLE_SOURCE_DATE_EPOCH}", 0, "1970-01-01T00:00:00Z"),
        "token.stamp": ("{STABLE_SOURCE_DATE_EPOCH}", 1, "2009-02-13T23:31:30Z"),
    }

    for variant, (annotation, stamp, expected) in variants.items():
        helm_package(
            name = "created.{}".format(variant),
            chart_json = _chart_json(annotation),
            templates = native.glob(["templates/**"]),
            values = "values.yaml",
            stamp = stamp,
        )

        _helm_pkg_metadata(
            name = "created.{}.metadata".format(variant),
            chart = ":created.{}".format(variant),
        )

        _metadata_golden("created.{}".format(variant), expected)

        diff_test(
            name = "created.{}.metadata_test".format(variant),
            file1 = "created.{}.expected_metadata".format(variant),
            file2 = "created.{}.metadata".format(variant),
        )
        tests.append("created.{}.metadata_test".format(variant))

    # Assert the packaged Chart.yaml carries canonical RFC3339, not the raw epoch
    # `1234567890`. The tar path uses the chart `name:` (`created`).
    native.genrule(
        name = "created.token.stamp.chart_created_line",
        srcs = [":created.token.stamp"],
        outs = ["created.token.stamp.chart_created_line.txt"],
        cmd = "tar -xzOf $(location :created.token.stamp) created/Chart.yaml | grep org.opencontainers.image.created > $@",
    )

    write_file(
        name = "created.token.stamp.expected_chart_created_line",
        out = "created.token.stamp.expected_chart_created_line.txt",
        content = [
            '  org.opencontainers.image.created: "2009-02-13T23:31:30Z"',
            "",
        ],
        newline = "unix",
    )

    diff_test(
        name = "created.token.stamp.normalization_test",
        file1 = "created.token.stamp.expected_chart_created_line",
        file2 = "created.token.stamp.chart_created_line",
    )
    tests.append("created.token.stamp.normalization_test")

    # A stamped chart yields a byte-identical OCI digest across builds: the
    # immutable-re-push guarantee.
    helm_chart(
        name = "created.digest",
        chart_json = _chart_json("{STABLE_SOURCE_DATE_EPOCH}"),
        templates = native.glob(["templates/**"]),
        values = "values.yaml",
        stamp = 1,
    )

    diff_test(
        name = "created.digest_test",
        file1 = "created.digest.oci_digest.golden",
        file2 = ":created.digest.oci_digest",
    )
    tests.append("created.digest_test")

    native.test_suite(
        name = name,
        tests = tests,
    )

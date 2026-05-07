"""Unittest to verify workspace status stamping is applied to environment files"""

load("@bazel_skylib//rules:diff_test.bzl", "diff_test")
load("@bazel_skylib//rules:write_file.bzl", "write_file")
load("//helm:defs.bzl", "helm_lint_test", "helm_package", "helm_template_test")
load("//helm:helm_package_info.bzl", "HelmPackageInfo")

def _helm_pkg_metadata_impl(ctx):
    src = ctx.attr.chart[HelmPackageInfo].metadata
    if not ctx.attr.stamp:
        return DefaultInfo(files = depset([src]))

    # Stamped builds embed time.Now() into `created`, so strip it before
    # diffing — the rest of the metadata is deterministic and worth pinning.
    out = ctx.actions.declare_file(ctx.label.name + ".filtered.json")
    ctx.actions.run_shell(
        inputs = [src],
        outputs = [out],
        command = "printf '%s' \"$(grep -v created {})\" > {}".format(src.path, out.path),
    )
    return DefaultInfo(files = depset([out]))

_helm_pkg_metadata = rule(
    implementation = _helm_pkg_metadata_impl,
    doc = "A helper rule for parsing helm metadata from a package",
    attrs = {
        "chart": attr.label(
            doc = "The `helm_package` target to parse metadata from",
            providers = [HelmPackageInfo],
            mandatory = True,
        ),
        "stamp": attr.bool(
            doc = "Whether to stamp the metadata with build time.",
            default = False,
        ),
    },
)

def version_stamp_test_suite(name):
    """Entry-point macro called from the BUILD file.

    Args:
        name (str): Name of the macro.
    """

    test_variants = {
        "no_stamp": 0,
        "stamp": 1,
    }

    for name, stamp_value in test_variants.items():
        helm_package(
            name = "version_stamp.{}".format(name),
            chart = "Chart.yaml",
            templates = native.glob(["templates/**"]),
            values = "values.yaml",
            stamp = stamp_value,
        )

        _helm_pkg_metadata(
            name = "version_stamp.{}.metadata".format(name),
            chart = ":version_stamp.{}".format(name),
            stamp = stamp_value,
        )

        helm_lint_test(
            name = "version_stamp.{}.lint_test".format(name),
            chart = ":version_stamp.{}".format(name),
        )

        helm_template_test(
            name = "version_stamp.{}.template_test".format(name),
            chart = ":version_stamp.{}".format(name),
        )

    write_file(
        name = "version_stamp.no_stamp.expected_metadata",
        out = "version_stamp.no_stamp.expected_metadata.json",
        content = """\
{
    "created": "1970-01-01T00:00:00Z",
    "name": "version-stamp",
    "version": "0.1.0+STABLE-STAMP-VALUE-VOLATILE-STAMP-VALUE"
}
""".splitlines(),
        newline = "unix",
    )

    diff_test(
        name = "version_stamp.no_stamp.diff_test",
        file1 = ":version_stamp.no_stamp.expected_metadata",
        file2 = ":version_stamp.no_stamp.metadata",
    )

    write_file(
        name = "version_stamp.stamp.expected_metadata",
        out = "version_stamp.stamp.expected_metadata.json",
        content = """\
{
    "name": "version-stamp",
    "version": "0.1.0+stable-volatile"
}
""".splitlines(),
        newline = "unix",
    )

    diff_test(
        name = "version_stamp.stamp.diff_test",
        file1 = ":version_stamp.stamp.expected_metadata",
        file2 = ":version_stamp.stamp.metadata",
    )

    native.test_suite(
        name = name,
        tests = [
            "version_stamp.stamp.lint_test",
            "version_stamp.no_stamp.lint_test",
            "version_stamp.stamp.diff_test",
            "version_stamp.no_stamp.diff_test",
        ],
    )

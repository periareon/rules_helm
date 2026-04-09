"""Build-time OCI digest computation for Helm charts."""

load(":providers.bzl", "HelmPackageInfo")

HelmOCIDigestInfo = provider(
    doc = "OCI manifest digest for a Helm chart, computed at build time.",
    fields = {
        "digest": "File: Text file containing the OCI manifest digest (sha256:...)",
        "manifest": "File: The OCI manifest JSON",
        "config": "File: The config blob JSON (Chart.yaml serialized with Helm field ordering)",
        "layout": "File: OCI layout directory (tree artifact) for crane push",
    },
)

def _helm_oci_digest_impl(ctx):
    pkg_info = ctx.attr.chart[HelmPackageInfo]

    digest_out = ctx.actions.declare_file(ctx.label.name + ".digest")
    manifest_out = ctx.actions.declare_file(ctx.label.name + ".manifest.json")
    config_out = ctx.actions.declare_file(ctx.label.name + ".config.json")
    layout_out = ctx.actions.declare_directory(ctx.label.name + ".oci_layout")

    args = ctx.actions.args()
    args.add("-chart", pkg_info.chart)
    args.add("-metadata", pkg_info.metadata)
    args.add("-digest_output", digest_out)
    args.add("-manifest_output", manifest_out)
    args.add("-config_output", config_out)
    args.add("-layout_output", layout_out.path)

    ctx.actions.run(
        executable = ctx.executable._oci_digest_tool,
        arguments = [args],
        inputs = [pkg_info.chart, pkg_info.metadata],
        outputs = [digest_out, manifest_out, config_out, layout_out],
        mnemonic = "HelmOCIDigest",
        progress_message = "Computing OCI digest for %s" % ctx.label,
    )

    return [
        DefaultInfo(
            files = depset([digest_out]),
        ),
        OutputGroupInfo(
            digest = depset([digest_out]),
            manifest = depset([manifest_out]),
            config = depset([config_out]),
            oci_layout = depset([layout_out]),
        ),
        HelmOCIDigestInfo(
            digest = digest_out,
            manifest = manifest_out,
            config = config_out,
            layout = layout_out,
        ),
        # Forward HelmPackageInfo so downstream rules (helm_oci_push)
        # can access both providers from a single target.
        ctx.attr.chart[HelmPackageInfo],
    ]

helm_oci_digest = rule(
    implementation = _helm_oci_digest_impl,
    doc = """Compute the OCI manifest digest for a Helm chart at build time.

This rule constructs the OCI manifest that `helm push` would create
(minus the non-deterministic timestamp annotation) and computes its
sha256 digest. The digest is available as a build output, enabling
deployment pinning without a push-time race condition.

It also produces an OCI layout directory suitable for `crane push`.

The digest file contains a single line: `sha256:<hex>`.
""",
    attrs = {
        "chart": attr.label(
            doc = "A helm_chart target providing HelmPackageInfo.",
            providers = [HelmPackageInfo],
            mandatory = True,
        ),
        "_oci_digest_tool": attr.label(
            doc = "The Go tool that computes the OCI digest and layout.",
            executable = True,
            cfg = "exec",
            default = Label("//helm/private/oci_digest"),
        ),
    },
)

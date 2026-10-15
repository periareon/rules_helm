"""Build-time OCI digest computation for Helm charts."""

load(":providers.bzl", "HelmPackageInfo")

HelmOCIDigestInfo = provider(
    doc = "OCI manifest digest for a Helm chart, computed at build time.",
    fields = {
        "config": "File: The raw OCI config blob (application/vnd.cncf.helm.config.v1+json)",
        "digest": "File: Text file containing the OCI manifest digest (sha256:...)",
        "manifest": "File: The raw OCI manifest bytes whose digest is in `digest`",
    },
)

def _helm_oci_digest_impl(ctx):
    pkg_info = ctx.attr.chart[HelmPackageInfo]

    digest_out = ctx.actions.declare_file(ctx.label.name + ".digest")
    manifest_out = ctx.actions.declare_file(ctx.label.name + ".manifest.json")
    config_out = ctx.actions.declare_file(ctx.label.name + ".config.json")

    args = ctx.actions.args()
    args.add("-chart", pkg_info.chart)
    args.add("-metadata", pkg_info.metadata)
    args.add("-digest_output", digest_out)
    args.add("-manifest_output", manifest_out)
    args.add("-config_output", config_out)

    ctx.actions.run(
        executable = ctx.executable._oci_digest_tool,
        arguments = [args],
        inputs = [pkg_info.chart, pkg_info.metadata],
        outputs = [digest_out, manifest_out, config_out],
        mnemonic = "HelmOCIDigest",
        progress_message = "Computing OCI digest for %s" % ctx.label,
    )

    return [
        DefaultInfo(
            files = depset([digest_out]),
        ),
        HelmOCIDigestInfo(
            digest = digest_out,
            manifest = manifest_out,
            config = config_out,
        ),
        # Also as output groups, so the blobs are reachable from a BUILD file
        # (filegroup, diff_test) and not only from a rule implementation.
        OutputGroupInfo(
            config = depset([config_out]),
            manifest = depset([manifest_out]),
        ),
        # Forward HelmPackageInfo so downstream rules can access
        # both providers from a single target.
        ctx.attr.chart[HelmPackageInfo],
    ]

helm_oci_digest = rule(
    implementation = _helm_oci_digest_impl,
    doc = """Compute the OCI manifest digest for a Helm chart at build time.

This rule constructs the OCI manifest that `helm push` (Helm v4) would
create and computes its sha256 digest. The creation annotation comes from
the chart's own `org.opencontainers.image.created` annotation, resolved by
the stamping pass, and is formatted in UTC to match the push side.

The digest file contains a single line: `sha256:<hex>`.

The manifest and config blobs are also emitted, so a pusher that uploads
them itself can PUT the exact bytes this digest was computed over. They are
not in the default outputs; read them off `HelmOCIDigestInfo`.
""",
    attrs = {
        "chart": attr.label(
            doc = "A helm_chart target providing HelmPackageInfo.",
            providers = [HelmPackageInfo],
            mandatory = True,
        ),
        "_oci_digest_tool": attr.label(
            doc = "The Go tool that computes the OCI digest.",
            executable = True,
            cfg = "exec",
            default = Label("//helm/private/oci_digest"),
        ),
    },
)

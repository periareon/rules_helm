"""Build-time OCI digest computation for Helm charts."""

load(":providers.bzl", "HelmPackageInfo")

HelmOCIDigestInfo = provider(
    doc = "OCI manifest digest for a Helm chart, computed at build time.",
    fields = {
        "annotations": "File: The manifest annotations, as a JSON object of strings",
        "config": "File: The raw OCI config blob (application/vnd.cncf.helm.config.v1+json)",
        "digest": "File: Text file containing the OCI manifest digest (sha256:...)",
        "manifest": "File: The raw OCI manifest bytes whose digest is in `digest`",
        "repository": "File: `<registry>/<repository>` that `helm push` pushes to, or `None` when no registry URL is set",
        "tag": "File: The tag `helm push` uses, which is the chart version with `+` replaced by `_`",
    },
)

def _helm_oci_digest_impl(ctx):
    if ctx.attr.registry_url and ctx.attr.registry_url_file:
        fail("`registry_url` and `registry_url_file` are mutually exclusive. Only one may be specified for target `{}`.".format(ctx.label))

    pkg_info = ctx.attr.chart[HelmPackageInfo]

    digest_out = ctx.actions.declare_file(ctx.label.name + ".digest")
    manifest_out = ctx.actions.declare_file(ctx.label.name + ".manifest.json")
    config_out = ctx.actions.declare_file(ctx.label.name + ".config.json")
    annotations_out = ctx.actions.declare_file(ctx.label.name + ".annotations.json")
    tag_out = ctx.actions.declare_file(ctx.label.name + ".tag.txt")
    inputs = [pkg_info.chart, pkg_info.metadata]
    outputs = [digest_out, manifest_out, config_out, annotations_out, tag_out]

    args = ctx.actions.args()
    args.add("-chart", pkg_info.chart)
    args.add("-metadata", pkg_info.metadata)
    args.add("-digest_output", digest_out)
    args.add("-manifest_output", manifest_out)
    args.add("-config_output", config_out)
    args.add("-annotations_output", annotations_out)
    args.add("-tag_output", tag_out)

    repository_out = None
    if ctx.attr.registry_url or ctx.attr.registry_url_file:
        repository_out = ctx.actions.declare_file(ctx.label.name + ".repository.txt")
        outputs.append(repository_out)
        args.add("-repository_output", repository_out)
        if ctx.attr.registry_url:
            args.add("-registry_url", ctx.attr.registry_url)
        else:
            args.add("-registry_url_file", ctx.file.registry_url_file)
            inputs.append(ctx.file.registry_url_file)

    ctx.actions.run(
        executable = ctx.executable._oci_digest_tool,
        arguments = [args],
        inputs = inputs,
        outputs = outputs,
        mnemonic = "HelmOCIDigest",
        progress_message = "Computing OCI digest for %s" % ctx.label,
    )

    output_groups = {
        "annotations": depset([annotations_out]),
        "config": depset([config_out]),
        "manifest": depset([manifest_out]),
        "tag": depset([tag_out]),
    }
    if repository_out:
        output_groups["repository"] = depset([repository_out])

    return [
        DefaultInfo(
            files = depset([digest_out]),
        ),
        HelmOCIDigestInfo(
            annotations = annotations_out,
            config = config_out,
            digest = digest_out,
            manifest = manifest_out,
            repository = repository_out,
            tag = tag_out,
        ),
        # Also as output groups, so the files are reachable from a BUILD file
        # (filegroup, diff_test) and not only from a rule implementation.
        OutputGroupInfo(**output_groups),
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
them itself can PUT the exact bytes this digest was computed over. The
manifest annotations and the tag are emitted for a pusher that builds the
manifest itself. With `registry_url` or `registry_url_file`, so is the
repository `helm push` would push to. None of these are in the default
outputs; read them off `HelmOCIDigestInfo` or its output groups.
""",
    attrs = {
        "chart": attr.label(
            doc = "A helm_chart target providing HelmPackageInfo.",
            providers = [HelmPackageInfo],
            mandatory = True,
        ),
        "registry_url": attr.string(
            doc = "The registry URL given to `helm push`, for example `oci://registry.example.com/charts`. Sets `HelmOCIDigestInfo.repository`. Only `oci://` URLs are accepted; any other scheme fails the target, digest included. Mutually exclusive with `registry_url_file`.",
        ),
        "registry_url_file": attr.label(
            doc = "A file containing the registry URL given to `helm push`. Sets `HelmOCIDigestInfo.repository`. As with `registry_url`, only `oci://` URLs are accepted. Mutually exclusive with `registry_url`.",
            allow_single_file = True,
        ),
        "_oci_digest_tool": attr.label(
            doc = "The Go tool that computes the OCI digest.",
            executable = True,
            cfg = "exec",
            default = Label("//helm/private/oci_digest"),
        ),
    },
)

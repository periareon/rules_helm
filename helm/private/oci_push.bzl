"""Push a Helm chart to an OCI registry using crane.

Unlike helm_push which delegates to `helm push` (constructing the OCI
manifest server-side with a non-deterministic timestamp), this rule
pushes a pre-built OCI layout using crane. The manifest digest is
known at build time and matches exactly what ends up in the registry.
"""

load("@bazel_lib//lib:paths.bzl", "BASH_RLOCATION_FUNCTION", "to_rlocation_path")
load(":oci_digest.bzl", "HelmOCIDigestInfo")
load(":providers.bzl", "HelmPackageInfo")

CRANE_TOOLCHAIN_TYPE = "@crane.bzl//crane/toolchain:type"

def _helm_oci_push_impl(ctx):
    crane_toolchain = ctx.toolchains[CRANE_TOOLCHAIN_TYPE]

    oci_info = ctx.attr.chart[HelmOCIDigestInfo]
    pkg_info = ctx.attr.chart[HelmPackageInfo]

    # Write version tag to a file from metadata at build time (no jq needed)
    tags_file = ctx.actions.declare_file(ctx.label.name + ".tags.txt")
    ctx.actions.run_shell(
        inputs = [pkg_info.metadata],
        outputs = [tags_file],
        command = "python3 -c \"import json; print(json.load(open('{}'))['version'])\" > {}".format(
            pkg_info.metadata.path,
            tags_file.path,
        ),
        mnemonic = "HelmOCITags",
    )

    executable = ctx.actions.declare_file("push_%s.sh" % ctx.label.name)
    files = [oci_info.layout, oci_info.digest, tags_file, crane_toolchain.crane_info.binary]

    # Collect image pushers when include_images is enabled
    image_pusher_paths = []
    image_runfiles = ctx.runfiles()
    if ctx.attr.include_images:
        image_pushers = []
        image_runfiles_list = []
        for image in pkg_info.images:
            pusher = image[DefaultInfo].files_to_run.executable
            image_pushers.append(pusher)
            image_runfiles_list.append(image[DefaultInfo].default_runfiles)

        files = files + image_pushers
        image_pusher_paths = [to_rlocation_path(ctx, p) for p in image_pushers]

        image_runfiles = ctx.runfiles(files = image_pushers)
        for ir in image_runfiles_list:
            image_runfiles = image_runfiles.merge(ir)

    substitutions = {
        "{{BASH_RLOCATION_FUNCTION}}": BASH_RLOCATION_FUNCTION,
        "{{crane_path}}": to_rlocation_path(ctx, crane_toolchain.crane_info.binary),
        "{{layout_dir}}": to_rlocation_path(ctx, oci_info.layout),
        "{{digest_file}}": to_rlocation_path(ctx, oci_info.digest),
        "{{tags_file}}": to_rlocation_path(ctx, tags_file),
        "{{fixed_args}}": "",
        "{{image_pushers}}": ",".join(image_pusher_paths),
    }

    if ctx.attr.repository:
        substitutions["{{fixed_args}}"] = "\"--repository\" \"{}\"".format(ctx.attr.repository)

    ctx.actions.expand_template(
        template = ctx.file._push_sh_tpl,
        output = executable,
        is_executable = True,
        substitutions = substitutions,
    )

    runfiles = ctx.runfiles(files = files)
    runfiles = runfiles.merge(crane_toolchain.default.default_runfiles)
    runfiles = runfiles.merge(ctx.attr._runfiles.default_runfiles)
    runfiles = runfiles.merge(image_runfiles)

    return [
        DefaultInfo(
            files = depset([executable]),
            executable = executable,
            runfiles = runfiles,
        ),
        HelmOCIDigestInfo(
            digest = oci_info.digest,
            manifest = oci_info.manifest,
            config = oci_info.config,
            layout = oci_info.layout,
        ),
    ]

helm_oci_push = rule(
    doc = """Push a Helm chart to an OCI registry using crane.

Pushes a pre-built OCI layout by digest, then tags with the chart version.
The manifest digest is deterministic and known at build time (available
via the HelmOCIDigestInfo provider).

The chart attribute must point to a helm_oci_digest target.

Example:
    helm_oci_digest(name = "myrelease_digest", chart = ":myrelease")
    helm_oci_push(
        name = "myrelease.push_gcp",
        chart = ":myrelease_digest",
        repository = "us-east1-docker.pkg.dev/myproject/charts/myrelease",
    )

Runtime usage:
    bazel run //:myrelease.push_gcp
    bazel run //:myrelease.push_gcp -- --tag extra-tag
""",
    implementation = _helm_oci_push_impl,
    executable = True,
    attrs = {
        "chart": attr.label(
            doc = "A helm_oci_digest target providing HelmOCIDigestInfo and HelmPackageInfo.",
            providers = [HelmOCIDigestInfo, HelmPackageInfo],
            mandatory = True,
        ),
        "include_images": attr.bool(
            doc = "If True, images depended on by the chart will be pushed before the chart.",
            default = False,
        ),
        "repository": attr.string(
            doc = "OCI repository to push to (without oci:// prefix). E.g. us-east1-docker.pkg.dev/myproject/charts/myrelease",
            mandatory = True,
        ),
        "_push_sh_tpl": attr.label(
            default = "oci_push.sh.tpl",
            allow_single_file = True,
        ),
        "_runfiles": attr.label(
            default = "@bazel_tools//tools/bash/runfiles",
        ),
    },
    toolchains = [CRANE_TOOLCHAIN_TYPE],
)

"""`HelmImageInfo` for images built with rules_oci."""

load("@rules_helm//helm:defs.bzl", "HelmImageInfo")

_OciPushInfo = provider(
    doc = "What `helm_oci_image` needs from an `oci_push` target.",
    fields = {
        "layout": "File: The OCI image layout being pushed.",
        "repository": "File: A single line, `<registry>/<repository>`.",
        "tags": "File (optional): The remote tags, one per line.",
    },
)

def _oci_push_aspect_impl(target, ctx):
    # `oci_push` provides nothing beyond `DefaultInfo`, so its attributes are
    # the only source of truth for where the image goes.
    if not hasattr(ctx.rule.file, "image") or not ctx.rule.file.image:
        fail("{} must be an `oci_push` target with an `image`".format(target.label))

    if getattr(ctx.rule.attr, "repository", None):
        repository = ctx.actions.declare_file("{}.rules_helm.repository.txt".format(target.label.name))
        ctx.actions.write(
            output = repository,
            content = ctx.rule.attr.repository,
        )
    elif getattr(ctx.rule.file, "repository_file", None):
        repository = ctx.rule.file.repository_file
    else:
        fail("{} must set either `repository` or `repository_file`".format(target.label))

    return [_OciPushInfo(
        layout = ctx.rule.file.image,
        repository = repository,
        tags = getattr(ctx.rule.file, "remote_tags", None),
    )]

_oci_push_aspect = aspect(
    doc = "Collects the push destination from an `oci_push` target's attributes.",
    implementation = _oci_push_aspect_impl,
)

def _helm_oci_image_impl(ctx):
    target = ctx.attr.image
    push = target[_OciPushInfo]

    # `oci_push` points at an OCI image layout. Lift the root manifest out of
    # it so the image is described the same way as every other provider.
    manifest = ctx.actions.declare_file("{}.manifest.json".format(ctx.label.name))
    args = ctx.actions.args()
    args.add("-layout", push.layout.path)
    args.add("-output", manifest)
    ctx.actions.run(
        executable = ctx.executable._layout_manifest,
        mnemonic = "HelmOciLayoutManifest",
        arguments = [args],
        inputs = [push.layout],
        outputs = [manifest],
    )

    return [
        DefaultInfo(files = depset([manifest])),
        HelmImageInfo(
            label = target.label,
            aliases = [],
            repository = push.repository,
            manifest = manifest,
            tags = push.tags,
            pusher = target[DefaultInfo].files_to_run.executable,
            runfiles = target[DefaultInfo].default_runfiles,
        ),
    ]

helm_oci_image = rule(
    doc = """\
Describe a `rules_oci` image to `rules_helm`.

Accepts an `oci_push` target and provides `HelmImageInfo` for the image it
pushes. Values keep referring to the wrapped target, e.g. `{@//app:image.push}`.
""",
    implementation = _helm_oci_image_impl,
    attrs = {
        "image": attr.label(
            doc = "An `oci_push` target.",
            mandatory = True,
            aspects = [_oci_push_aspect],
        ),
        "_layout_manifest": attr.label(
            doc = "Tool for copying the root manifest out of an OCI image layout",
            cfg = "exec",
            executable = True,
            default = Label("@rules_helm//helm/private/layout_manifest"),
        ),
    },
    provides = [HelmImageInfo],
)

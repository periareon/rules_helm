"""Helm rules"""

load(":helm_utils.bzl", "rlocationpath", "symlink")
load(":providers.bzl", "HelmPackageInfo")

def _get_image_push_commands(ctx, pkg_info):
    image_pushers = []
    image_runfiles = []
    for image in pkg_info.images:
        image_pushers.append(image[DefaultInfo].files_to_run.executable)
        image_runfiles.append(image[DefaultInfo].default_runfiles)

    runfiles = ctx.runfiles(files = image_pushers)
    for ir in image_runfiles:
        runfiles = runfiles.merge(ir)
    return image_pushers, runfiles

def _helm_push_impl(ctx):
    toolchain = ctx.toolchains[Label("//helm:toolchain_type")]

    if toolchain.helm.basename.endswith(".exe"):
        registrar = ctx.actions.declare_file(ctx.label.name + ".exe")
    else:
        registrar = ctx.actions.declare_file(ctx.label.name)

    symlink(
        ctx = ctx,
        target_file = ctx.executable._registrar,
        output = registrar,
        is_executable = True,
    )

    pkg_info = ctx.attr.package[HelmPackageInfo]

    args = ctx.actions.args()
    args.set_param_file_format("multiline")
    args.add("-helm", rlocationpath(toolchain.helm, ctx.workspace_name))
    args.add("-helm_plugins", rlocationpath(toolchain.helm_plugins, ctx.workspace_name))
    args.add("-chart", rlocationpath(pkg_info.chart, ctx.workspace_name))
    args.add("-registry_url", ctx.attr.registry_url)

    if ctx.attr.login_url:
        args.add("-login_url", ctx.attr.login_url)

    if ctx.attr.push_cmd:
        args.add("-push_cmd", ctx.attr.push_cmd)

    image_runfiles = ctx.runfiles()
    if ctx.attr.include_images:
        image_pushers, image_runfiles = _get_image_push_commands(
            ctx = ctx,
            pkg_info = pkg_info,
        )

        if image_pushers:
            args.add("-image_pushers", ",".join([rlocationpath(p, ctx.workspace_name) for p in image_pushers]))

    args_file = ctx.actions.declare_file("{}.args.txt".format(ctx.label.name))
    ctx.actions.write(
        output = args_file,
        content = args,
    )

    runfiles = ctx.runfiles([
        registrar,
        args_file,
        toolchain.helm,
        toolchain.helm_plugins,
        pkg_info.chart,
    ]).merge(image_runfiles)

    return [
        DefaultInfo(
            files = depset([registrar]),
            runfiles = runfiles,
            executable = registrar,
        ),
        RunEnvironmentInfo(
            environment = ctx.attr.env | {
                "RULES_HELM_HELM_PUSH_ARGS_FILE": rlocationpath(args_file, ctx.workspace_name),
            },
        ),
    ]

helm_push = rule(
    doc = """\
Produce an executable for performing a helm push to a registry.

Before performing `helm push` the executable produced will conditionally perform [`helm registry login`](https://helm.sh/docs/helm/helm_registry_login/)
if the following environment variables are defined:
- `HELM_REGISTRY_USERNAME`: The value of `--username`.
- `HELM_REGISTRY_PASSWORD`/`HELM_REGISTRY_PASSWORD_FILE`: The value of `--password` or a file containing the `--password` value.
""",
    implementation = _helm_push_impl,
    executable = True,
    attrs = {
        "env": attr.string_dict(
            doc = "Environment variables to set when running this target.",
        ),
        "include_images": attr.bool(
            doc = "If True, images depended on by `package` will be pushed as well.",
            default = False,
        ),
        "login_url": attr.string(
            doc = "The URL of the registry to use for `helm login`. E.g. `my.registry.io`",
        ),
        "package": attr.label(
            doc = "The helm package to push to the registry.",
            providers = [HelmPackageInfo],
            mandatory = True,
        ),
        "push_cmd": attr.string(
            doc = "An alternative command to `push` for publishing the helm chart. E.g. `cm-push`",
        ),
        "registry_url": attr.string(
            doc = "The registry URL at which to push the helm chart to. E.g. `oci://my.registry.io/chart-name`",
            mandatory = True,
        ),
        "_copier": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("//helm/private/copier"),
        ),
        "_registrar": attr.label(
            doc = "A process wrapper to use for performing `helm registry and helm push`.",
            executable = True,
            cfg = "exec",
            default = Label("//helm/private/registrar"),
        ),
    },
    toolchains = [
        str(Label("//helm:toolchain_type")),
    ],
)

def _helm_push_images_impl(ctx):
    toolchain = ctx.toolchains[Label("//helm:toolchain_type")]

    if toolchain.helm.basename.endswith(".exe"):
        pusher = ctx.actions.declare_file(ctx.label.name + ".bat")
    else:
        pusher = ctx.actions.declare_file(ctx.label.name + ".sh")

    pkg_info = ctx.attr.package[HelmPackageInfo]

    image_pushers, image_runfiles = _get_image_push_commands(
        ctx = ctx,
        pkg_info = pkg_info,
    )

    image_commands = "\n".join([file.short_path for file in image_pushers])

    ctx.actions.expand_template(
        template = ctx.file._pusher,
        output = pusher,
        substitutions = {
            "{image_pushers}": image_commands,
        },
        is_executable = True,
    )

    runfiles = ctx.runfiles([pusher]).merge(image_runfiles)

    return [
        DefaultInfo(
            files = depset([pusher]),
            runfiles = runfiles,
            executable = pusher,
        ),
        RunEnvironmentInfo(
            environment = ctx.attr.env,
        ),
    ]

helm_push_images = rule(
    doc = "Produce an executable for pushing all oci images used by a helm chart.",
    implementation = _helm_push_images_impl,
    executable = True,
    attrs = {
        "env": attr.string_dict(
            doc = "Environment variables to set when running this target.",
        ),
        "package": attr.label(
            doc = "The helm package to upload images from.",
            providers = [HelmPackageInfo],
            mandatory = True,
        ),
        "_pusher": attr.label(
            doc = "A template used to produce the pusher executable.",
            allow_single_file = True,
            default = Label("//helm/private/pusher:template"),
        ),
    },
    toolchains = [
        str(Label("//helm:toolchain_type")),
    ],
)

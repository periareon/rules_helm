"""Helm rules"""

load(":helm_utils.bzl", "rlocationpath", "symlink")
load(":providers.bzl", "HelmPackageInfo")

def _get_image_push_commands(ctx, pkg_info):
    image_pushers = []
    image_runfiles = []
    for image in pkg_info.images:
        executable = image[DefaultInfo].files_to_run.executable
        if executable:
            image_pushers.append(executable)
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

    if ctx.attr.opts:
        args.add("--")
        args.add_all(ctx.attr.opts)

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
        "opts": attr.string_list(
            doc = "Additional arguments to pass to `helm` commands.",
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
        pusher_wrapper = ctx.actions.declare_file(ctx.label.name + ".exe")
    else:
        pusher_wrapper = ctx.actions.declare_file(ctx.label.name)

    symlink(
        ctx = ctx,
        target_file = ctx.executable._pusher,
        output = pusher_wrapper,
        is_executable = True,
    )

    pkg_info = ctx.attr.package[HelmPackageInfo]

    image_pushers, image_runfiles = _get_image_push_commands(
        ctx = ctx,
        pkg_info = pkg_info,
    )

    args = ctx.actions.args()
    args.set_param_file_format("multiline")
    for p in image_pushers:
        args.add(rlocationpath(p, ctx.workspace_name))

    args_file = ctx.actions.declare_file("{}.args.txt".format(ctx.label.name))
    ctx.actions.write(
        output = args_file,
        content = args,
    )

    runfiles = ctx.runfiles([
        pusher_wrapper,
        args_file,
    ]).merge(image_runfiles)

    return [
        DefaultInfo(
            files = depset([pusher_wrapper]),
            runfiles = runfiles,
            executable = pusher_wrapper,
        ),
        RunEnvironmentInfo(
            environment = ctx.attr.env | {
                "RULES_HELM_PUSHER_ARGS_FILE": rlocationpath(args_file, ctx.workspace_name),
            },
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
        "_copier": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("//helm/private/copier"),
        ),
        "_pusher": attr.label(
            doc = "A process wrapper to use for pushing images.",
            executable = True,
            cfg = "exec",
            default = Label("//helm/private/pusher"),
        ),
    },
    toolchains = [
        str(Label("//helm:toolchain_type")),
    ],
)

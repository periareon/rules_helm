"""Helm rules"""

load(":helm_utils.bzl", "is_stamping_enabled", "rlocationpath", "symlink")
load(":providers.bzl", "HelmPackageInfo")

HelmInstallInfo = provider(
    doc = "Info about a helm installer.",
    fields = {
        "args_file": "File: The arguments file generated for the install command.",
    },
)

def _stamp_args_file(
        *,
        ctx,
        helm_toolchain,
        raw_args,
        output,
        chart = None,
        image_pushers = []):
    inputs = []

    stamper_args = ctx.actions.args()
    stamper_args.add("-output", output)

    if is_stamping_enabled(ctx.attr):
        stamper_args.add("-stable_status_file", ctx.info_file)
        stamper_args.add("-volatile_status_file", ctx.version_file)
        inputs.extend([ctx.info_file, ctx.version_file])

    stamper_args.add("--")

    runner_args = ctx.actions.args()

    if chart:
        runner_args.add("-chart", rlocationpath(chart, ctx.workspace_name))
        inputs.append(chart)

    runner_args.add("-helm", rlocationpath(helm_toolchain.helm, ctx.workspace_name))
    runner_args.add("-helm_plugins", rlocationpath(helm_toolchain.helm_plugins, ctx.workspace_name))

    if image_pushers:
        runner_args.add("-image_pushers", ",".join([rlocationpath(p, ctx.workspace_name) for p in image_pushers]))

    runner_args.add("--")

    ctx.actions.run(
        mnemonic = "HelmInstallStamp",
        executable = ctx.executable._stamper,
        arguments = [stamper_args, runner_args, raw_args],
        inputs = inputs,
        outputs = [output],
    )

    return output

def _expand_opts(ctx, opts, targets):
    return [ctx.expand_location(x, targets = targets) for x in opts]

def _helm_install_impl(ctx, subcommand = "install"):
    toolchain = ctx.toolchains[Label("//helm:toolchain_type")]

    if toolchain.helm.basename.endswith(".exe"):
        runner_wrapper = ctx.actions.declare_file(ctx.label.name + ".exe")
    else:
        runner_wrapper = ctx.actions.declare_file(ctx.label.name)

    symlink(
        ctx = ctx,
        target_file = ctx.executable._runner,
        output = runner_wrapper,
    )

    install_name = ctx.attr.install_name or ctx.label.name

    pkg_info = ctx.attr.package[HelmPackageInfo]

    image_pushers = []
    image_runfiles = []
    for image in pkg_info.images:
        image_pushers.append(image[DefaultInfo].files_to_run.executable)
        image_runfiles.append(image[DefaultInfo].default_runfiles)

    args = ctx.actions.args()
    args.add_all(_expand_opts(ctx, ctx.attr.helm_opts, ctx.attr.data))
    args.add(subcommand)
    args.add_all(_expand_opts(ctx, ctx.attr.opts, ctx.attr.data))
    args.add(install_name)
    args.add(rlocationpath(pkg_info.chart, ctx.workspace_name))

    args_file = _stamp_args_file(
        ctx = ctx,
        helm_toolchain = toolchain,
        chart = pkg_info.chart,
        image_pushers = image_pushers,
        raw_args = args,
        output = ctx.actions.declare_file("{}.args.txt".format(ctx.label.name)),
    )

    runfiles = ctx.runfiles([
        args_file,
        runner_wrapper,
        ctx.executable._runner,
        toolchain.helm,
        toolchain.helm_plugins,
        pkg_info.chart,
    ] + image_pushers + ctx.files.data)

    for ir in image_runfiles:
        runfiles = runfiles.merge(ir)

    return [
        DefaultInfo(
            files = depset([runner_wrapper]),
            runfiles = runfiles,
            executable = runner_wrapper,
        ),
        RunEnvironmentInfo(
            environment = {
                "RULES_HELM_HELM_RUNNER_ARGS_FILE": rlocationpath(args_file, ctx.workspace_name),
            },
        ),
        HelmInstallInfo(
            args_file = args_file,
        ),
    ]

helm_install = rule(
    doc = "Produce an executable for performing a `helm install` operation.",
    implementation = _helm_install_impl,
    executable = True,
    attrs = {
        "data": attr.label_list(
            doc = "Additional data to pass to `helm install`.",
            allow_files = True,
            mandatory = False,
        ),
        "helm_opts": attr.string_list(
            doc = "Additional arguments to pass to `helm` during install.",
        ),
        "install_name": attr.string(
            doc = "The name to use for the `helm install` command. The target name will be used if unset.",
        ),
        "opts": attr.string_list(
            doc = "Additional arguments to pass to `helm install`.",
        ),
        "package": attr.label(
            doc = "The helm package to install.",
            providers = [HelmPackageInfo],
            mandatory = True,
        ),
        "_copier": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("//helm/private/copier"),
        ),
        "_runner": attr.label(
            doc = "A process wrapper to use for performing `helm install`.",
            executable = True,
            cfg = "exec",
            default = Label("//helm/private/runner"),
        ),
        "_stamp_flag": attr.label(
            doc = "A setting used to determine whether or not the `--stamp` flag is enabled",
            default = Label("//helm/private:stamp"),
        ),
        "_stamper": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("//helm/private/stamper"),
        ),
    },
    toolchains = [
        str(Label("//helm:toolchain_type")),
    ],
)

def _helm_upgrade_impl(ctx):
    return _helm_install_impl(ctx, "upgrade")

helm_upgrade = rule(
    doc = "Produce an executable for performing a `helm upgrade` operation.",
    implementation = _helm_upgrade_impl,
    executable = True,
    attrs = {
        "data": attr.label_list(
            doc = "Additional data to pass to `helm upgrade`.",
            allow_files = True,
            mandatory = False,
        ),
        "helm_opts": attr.string_list(
            doc = "Additional arguments to pass to `helm` during upgrade.",
        ),
        "install_name": attr.string(
            doc = "The name to use for the `helm upgrade` command. The target name will be used if unset.",
        ),
        "opts": attr.string_list(
            doc = "Additional arguments to pass to `helm upgrade`.",
        ),
        "package": attr.label(
            doc = "The helm package to upgrade.",
            providers = [HelmPackageInfo],
            mandatory = True,
        ),
        "_copier": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("//helm/private/copier"),
        ),
        "_runner": attr.label(
            doc = "A process wrapper to use for performing `helm install`.",
            executable = True,
            cfg = "exec",
            default = Label("//helm/private/runner"),
        ),
        "_stamp_flag": attr.label(
            doc = "A setting used to determine whether or not the `--stamp` flag is enabled",
            default = Label("//helm/private:stamp"),
        ),
        "_stamper": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("//helm/private/stamper"),
        ),
    },
    toolchains = [
        str(Label("//helm:toolchain_type")),
    ],
)

def _helm_uninstall_impl(ctx):
    toolchain = ctx.toolchains[Label("//helm:toolchain_type")]

    if toolchain.helm.basename.endswith(".exe"):
        runner_wrapper = ctx.actions.declare_file(ctx.label.name + ".exe")
    else:
        runner_wrapper = ctx.actions.declare_file(ctx.label.name)

    symlink(
        ctx = ctx,
        target_file = ctx.executable._runner,
        output = runner_wrapper,
    )

    install_name = ctx.attr.install_name or ctx.label.name

    args = ctx.actions.args()
    args.add_all(_expand_opts(ctx, ctx.attr.helm_opts, ctx.attr.data))
    args.add("uninstall")
    args.add_all(_expand_opts(ctx, ctx.attr.opts, ctx.attr.data))
    args.add(install_name)

    args_file = _stamp_args_file(
        ctx = ctx,
        helm_toolchain = toolchain,
        raw_args = args,
        output = ctx.actions.declare_file("{}.args.txt".format(ctx.label.name)),
    )

    runfiles = ctx.runfiles([
        args_file,
        runner_wrapper,
        ctx.executable._runner,
        toolchain.helm,
        toolchain.helm_plugins,
    ] + ctx.files.data)

    return [
        DefaultInfo(
            files = depset([runner_wrapper]),
            runfiles = runfiles,
            executable = runner_wrapper,
        ),
        RunEnvironmentInfo(
            environment = {
                "RULES_HELM_HELM_RUNNER_ARGS_FILE": rlocationpath(args_file, ctx.workspace_name),
            },
        ),
    ]

helm_uninstall = rule(
    doc = "Produce an executable for performing a `helm uninstall` operation.",
    implementation = _helm_uninstall_impl,
    executable = True,
    attrs = {
        "data": attr.label_list(
            doc = "Additional data to pass to `helm uninstall`.",
            allow_files = True,
            mandatory = False,
        ),
        "helm_opts": attr.string_list(
            doc = "Additional arguments to pass to `helm` during install.",
        ),
        "install_name": attr.string(
            doc = "The name to use for the `helm install` command. The target name will be used if unset.",
        ),
        "opts": attr.string_list(
            doc = "Additional arguments to pass to `helm uninstall`.",
        ),
        "_copier": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("//helm/private/copier"),
        ),
        "_runner": attr.label(
            doc = "A process wrapper to use for performing `helm install`.",
            executable = True,
            cfg = "exec",
            default = Label("//helm/private/runner"),
        ),
        "_stamp_flag": attr.label(
            doc = "A setting used to determine whether or not the `--stamp` flag is enabled",
            default = Label("//helm/private:stamp"),
        ),
        "_stamper": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("//helm/private/stamper"),
        ),
    },
    toolchains = [
        str(Label("//helm:toolchain_type")),
    ],
)

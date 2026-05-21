"""Helm rules"""

load(":helm_utils.bzl", "rlocationpath", "symlink")
load(":install.bzl", "HelmInstallInfo", _expand_opts = "expand_opts", _stamp_args_file = "stamp_args_file")
load(":providers.bzl", "HelmPackageInfo")

def _helm_command_impl(ctx):
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

    pkg_info = ctx.attr.package[HelmPackageInfo] if ctx.attr.package else None
    chart = pkg_info.chart if pkg_info else None

    args = ctx.actions.args()
    args.add_all(_expand_opts(ctx, ctx.attr.helm_opts, ctx.attr.data))
    args.add_all(ctx.attr.command)
    args.add_all(_expand_opts(ctx, ctx.attr.opts, ctx.attr.data))
    if ctx.attr.install_name:
        args.add(ctx.attr.install_name)
    if chart:
        args.add(rlocationpath(chart, ctx.workspace_name))

    args_file = _stamp_args_file(
        ctx = ctx,
        helm_toolchain = toolchain,
        raw_args = args,
        output = ctx.actions.declare_file("{}.args.txt".format(ctx.label.name)),
        chart = chart,
        values = ctx.files.values,
    )

    direct_files = [
        args_file,
        runner_wrapper,
        ctx.executable._runner,
        toolchain.helm,
        toolchain.helm_plugins,
    ] + ctx.files.data + ctx.files.values
    if chart:
        direct_files.append(chart)
    runfiles = ctx.runfiles(direct_files)

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

helm_command = rule(
    doc = """\
Produce an executable that invokes `helm` with an arbitrary subcommand. \
Useful for wrapping helm plugins (e.g. [helm-diff](https://github.com/databus23/helm-diff)) \
without requiring a dedicated rule for each plugin.

Example:

```python
load("@rules_helm//helm:defs.bzl", "helm_command")

helm_command(
    name = "my_chart.diff",
    command = ["diff", "upgrade"],
    install_name = "my-chart",
    package = ":my_chart",
)
```

Any helm plugin referenced by `command` must be registered in the active helm \
toolchain (see [helm_plugin](#helm_plugin) / [helm_toolchain](#helm_toolchain)).\
""",
    implementation = _helm_command_impl,
    executable = True,
    attrs = {
        "command": attr.string_list(
            doc = "Subcommand tokens placed between `helm_opts` and `opts` (e.g. `[\"diff\", \"upgrade\"]`).",
            mandatory = True,
            allow_empty = False,
        ),
        "data": attr.label_list(
            doc = "Additional data to pass to the helm invocation.",
            allow_files = True,
            mandatory = False,
        ),
        "helm_opts": attr.string_list(
            doc = "Additional arguments to pass to `helm` before the subcommand.",
        ),
        "install_name": attr.string(
            doc = "Release name appended as a positional after `opts`. Omitted when unset.",
        ),
        "opts": attr.string_list(
            doc = "Additional arguments to pass after the subcommand.",
        ),
        "package": attr.label(
            doc = "Optional helm package. When set, its chart path is appended as the final positional argument.",
            providers = [HelmPackageInfo],
            mandatory = False,
        ),
        "values": attr.label_list(
            doc = "Values files to pass to the subcommand via `--values`.",
            allow_files = True,
        ),
        "_copier": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("//helm/private/copier"),
        ),
        "_runner": attr.label(
            doc = "A process wrapper to use for invoking `helm`.",
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

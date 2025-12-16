"""Helm rules"""

load(":helm_install.bzl", "HelmInstallInfo")
load(":helm_utils.bzl", "rlocationpath", "symlink")
load(":providers.bzl", "HelmPackageInfo")

def _helm_template_test_impl(ctx):
    toolchain = ctx.toolchains[Label("//helm:toolchain_type")]

    if ctx.attr.installer and ctx.attr.chart:
        fail("`installer` and `package` attributes are mutually exclusive. Please select only one for {}".format(
            ctx.label,
        ))

    template_patterns = None
    if ctx.attr.template_patterns:
        template_patterns = ctx.actions.declare_file("{}.template_patterns.json".format(ctx.label.name))
        ctx.actions.write(
            output = template_patterns,
            content = json.encode_indent(ctx.attr.template_patterns, indent = " " * 4),
        )

    args_file = None
    runfiles = ctx.runfiles()
    if ctx.attr.installer:
        installer = ctx.attr.installer
        installer_info = ctx.attr.installer[HelmInstallInfo]
        runfiles = runfiles.merge(installer[DefaultInfo].default_runfiles)
        args_file = installer_info.args_file

    elif ctx.attr.chart:
        package = ctx.attr.chart
        pkg_info = package[HelmPackageInfo]

        args_file = ctx.actions.declare_file("{}.args.txt".format(ctx.label.name))
        args = ctx.actions.args()
        args.set_param_file_format("multiline")
        args.add("-chart", rlocationpath(pkg_info.chart, ctx.workspace_name))
        args.add("-helm", rlocationpath(toolchain.helm, ctx.workspace_name))
        args.add("-helm_plugins", rlocationpath(toolchain.helm_plugins, ctx.workspace_name))
        args.add("--")
        args.add("template")
        args.add(rlocationpath(pkg_info.chart, ctx.workspace_name))

        ctx.actions.write(
            output = args_file,
            content = args,
        )

        runfiles = runfiles.merge(ctx.runfiles([
            args_file,
            ctx.executable._runner,
            toolchain.helm,
            toolchain.helm_plugins,
            pkg_info.chart,
        ]))

    else:
        fail("`installer` or `chart` attributes are required. Please update {}".format(
            ctx.label,
        ))

    if toolchain.helm.basename.endswith(".exe"):
        runner_wrapper = ctx.actions.declare_file(ctx.label.name + ".exe")
    else:
        runner_wrapper = ctx.actions.declare_file(ctx.label.name)

    symlink(
        ctx = ctx,
        target_file = ctx.executable._runner,
        output = runner_wrapper,
    )

    env = {
        "RULES_HELM_HELM_RUNNER_ARGS_FILE": rlocationpath(args_file, ctx.workspace_name),
        "RULES_HELM_HELM_TEMPLATE_TEST": "1",
    }

    if template_patterns:
        runfiles = runfiles.merge(ctx.runfiles(files = [template_patterns]))
        env["RULES_HELM_HELM_TEMPLATE_TEST_PATTERNS"] = rlocationpath(template_patterns, ctx.workspace_name)

    return [
        DefaultInfo(
            files = depset([runner_wrapper]),
            runfiles = runfiles,
            executable = runner_wrapper,
        ),
        RunEnvironmentInfo(
            environment = env,
        ),
    ]

helm_template_test = rule(
    doc = "A test rule for rendering helm chart templates.",
    implementation = _helm_template_test_impl,
    test = True,
    attrs = {
        "chart": attr.label(
            doc = "The helm package to resolve templates for. Mutually exclusive with `installer`.",
            mandatory = True,
            providers = [HelmPackageInfo],
        ),
        "installer": attr.label(
            doc = "The `helm_install`/`helm_upgrade` target to resolve templates for. Mutually exclusive with `chart`.",
            providers = [HelmInstallInfo],
        ),
        "template_patterns": attr.string_list_dict(
            doc = "A mapping of template paths to regex patterns required to match.",
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
    },
    toolchains = [
        str(Label("//helm:toolchain_type")),
    ],
)

def _helm_template_impl(ctx):
    toolchain = ctx.toolchains[Label("//helm:toolchain_type")]

    chart_info = ctx.attr.chart[HelmPackageInfo]

    output = ctx.outputs.out if ctx.outputs.out else ctx.actions.declare_file(ctx.label.name + ".yaml")

    args = ctx.actions.args()
    args.add("-helm", toolchain.helm)
    args.add("-helm_plugins", toolchain.helm_plugins.path)
    args.add("-chart", chart_info.chart)
    args.add("-output", output)

    for values in ctx.files.values:
        args.add("-values", values)

    ctx.actions.run(
        executable = ctx.executable._templater,
        outputs = [output],
        inputs = depset([chart_info.chart] + ctx.files.values),
        tools = depset([toolchain.helm, toolchain.helm_plugins]),
        mnemonic = "HelmTemplate",
        arguments = [args],
        progress_message = "Running Helm Template for {}".format(ctx.label),
    )

    return DefaultInfo(
        files = depset([output]),
        runfiles = ctx.runfiles([output]),
    )

helm_template = rule(
    doc = "A rule for rendering helm chart templates to a file.",
    implementation = _helm_template_impl,
    attrs = {
        "chart": attr.label(
            doc = "The helm package to resolve charts for.",
            mandatory = True,
            providers = [HelmPackageInfo],
        ),
        "out": attr.output(
            doc = "The output file to write the output from `helm template`.",
        ),
        "values": attr.label_list(
            doc = "Values files to pass to `helm template --values`.",
            allow_files = [".yml", ".yaml"],
        ),
        "_templater": attr.label(
            doc = "A process wrapper to use for running `helm template`.",
            executable = True,
            cfg = "exec",
            default = Label("//helm/private/templater"),
        ),
    },
    toolchains = [
        str(Label("//helm:toolchain_type")),
    ],
)

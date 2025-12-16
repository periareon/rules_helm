"""Helm rules"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(":helm_utils.bzl", "rlocationpath", "symlink")
load(":providers.bzl", "HelmPackageInfo")

def _helm_lint_aspect_impl(target, ctx):
    if HelmPackageInfo not in target:
        return []

    # Skip targets tagged for no-lint
    ignore_tags = [
        "no_helm_lint",
        "no_lint",
        "nolint",
        "nohelmlint",
    ]
    for tag in ctx.rule.attr.tags:
        if tag.replace("-", "_").lower() in ignore_tags:
            return []

    helm_pkg_info = target[HelmPackageInfo]
    toolchain = ctx.toolchains[Label("//helm:toolchain_type")]
    strict = ctx.attr._strict_setting[BuildSettingInfo].value

    output = ctx.actions.declare_file(ctx.label.name + ".helm_lint.ok")

    args = ctx.actions.args()
    args.add("-helm", toolchain.helm)
    args.add("-helm_plugins", toolchain.helm_plugins.path)
    args.add("-package", helm_pkg_info.chart)
    args.add("-output", output)
    if strict:
        args.add("-strict")

    ctx.actions.run(
        outputs = [output],
        executable = ctx.executable._linter,
        mnemonic = "HelmLintCheck",
        inputs = [helm_pkg_info.chart],
        tools = [toolchain.helm, toolchain.helm_plugins],
        arguments = [args],
    )

    return [
        OutputGroupInfo(
            helm_lint_checks = depset([output]),
        ),
    ]

helm_lint_aspect = aspect(
    doc = "An aspect for running `helm lint` on helm package targets",
    implementation = _helm_lint_aspect_impl,
    attrs = {
        "_linter": attr.label(
            doc = "A process wrapper for performing the linting.",
            cfg = "exec",
            executable = True,
            default = Label("//helm/private/linter:linter"),
        ),
        "_strict_setting": attr.label(
            default = Label("//helm/settings:lint_default_strict"),
        ),
    },
    toolchains = [
        str(Label("//helm:toolchain_type")),
    ],
)

def _helm_lint_test_impl(ctx):
    args_file = ctx.actions.declare_file(ctx.label.name + ".args.txt")

    helm_pkg_info = ctx.attr.chart[HelmPackageInfo]
    toolchain = ctx.toolchains[Label("//helm:toolchain_type")]

    args = ctx.actions.args()
    args.set_param_file_format("multiline")
    args.add("-helm", rlocationpath(toolchain.helm, ctx.workspace_name))
    args.add("-helm_plugins", rlocationpath(toolchain.helm_plugins, ctx.workspace_name))
    args.add("-package", rlocationpath(helm_pkg_info.chart, ctx.workspace_name))

    strict = ctx.attr._strict_setting[BuildSettingInfo].value
    if strict:
        args.add("-strict")

    # Passed directly to --set flag of `helm lint`, but using -substitutions to match helm_package.bzl.
    args.add("-substitutions", ",".join(["%s=%s" % (k, v) for k, v in ctx.attr.substitutions.items()]))

    # args_all with map_each can't be used here since the function can only
    # accept one argument and Bazel doesn't allow inline functions.
    for v in ctx.files.values:
        args.add("-values", rlocationpath(v, ctx.workspace_name))

    ctx.actions.write(
        output = args_file,
        content = args,
    )

    if toolchain.helm.basename.endswith(".exe"):
        test_runner = ctx.actions.declare_file(ctx.label.name + ".exe")
    else:
        test_runner = ctx.actions.declare_file(ctx.label.name)

    symlink(
        ctx = ctx,
        output = test_runner,
        target_file = ctx.executable._linter,
        is_executable = True,
    )

    return [
        DefaultInfo(
            files = depset([test_runner]),
            runfiles = ctx.runfiles(
                files = [toolchain.helm, toolchain.helm_plugins, helm_pkg_info.chart, args_file] + ctx.files.values,
            ).merge(ctx.attr._linter[DefaultInfo].default_runfiles),
            executable = test_runner,
        ),
        testing.TestEnvironment({
            "RULES_HELM_HELM_LINT_TEST_ARGS_PATH": rlocationpath(args_file, ctx.workspace_name),
        }),
    ]

helm_lint_test = rule(
    implementation = _helm_lint_test_impl,
    doc = "A rule for performing `helm lint` on a helm package",
    attrs = {
        "chart": attr.label(
            doc = "The helm package to run linting on.",
            mandatory = True,
            providers = [HelmPackageInfo],
        ),
        "substitutions": attr.string_dict(
            doc = "A dictionary of substitutions passed to `helm lint --set flag.",
            default = {},
        ),
        "values": attr.label_list(
            doc = "A list of files passed to `helm lint --values flag.",
            default = [],
            allow_files = True,
        ),
        "_copier": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("//helm/private/copier"),
        ),
        "_linter": attr.label(
            doc = "A process wrapper for performing the linting.",
            cfg = "exec",
            executable = True,
            default = Label("//helm/private/linter:linter"),
        ),
        "_strict_setting": attr.label(
            default = Label("//helm/settings:lint_default_strict"),
        ),
    },
    toolchains = [
        str(Label("//helm:toolchain_type")),
    ],
    test = True,
)

"""Test utilities for helm_command with toolchain transitions."""

# buildifier: disable=bzl-visibility
load("//helm/private:install.bzl", "HelmInstallInfo")

_PLUGIN_TOOLCHAIN_LABELS = [
    "@with_cm_push_toolchains//:with_cm_push__4.2.0_darwin_amd64_helm_bin",
    "@with_cm_push_toolchains//:with_cm_push__4.2.0_darwin_arm64_helm_bin",
    "@with_cm_push_toolchains//:with_cm_push__4.2.0_linux_amd64_helm_bin",
    "@with_cm_push_toolchains//:with_cm_push__4.2.0_linux_arm64_helm_bin",
    "@with_cm_push_toolchains//:with_cm_push__4.2.0_windows_amd64_helm_bin",
]

def _rlocationpath(file, workspace_name):
    if file.short_path.startswith("../"):
        return file.short_path[len("../"):]
    return "{}/{}".format(workspace_name, file.short_path)

def _helm_toolchain_transition_impl(settings, _attr):
    extra = list(settings["//command_line_option:extra_toolchains"])
    for label in reversed(_PLUGIN_TOOLCHAIN_LABELS):
        extra.insert(0, label)
    return {"//command_line_option:extra_toolchains": extra}

_helm_toolchain_transition = transition(
    implementation = _helm_toolchain_transition_impl,
    inputs = ["//command_line_option:extra_toolchains"],
    outputs = ["//command_line_option:extra_toolchains"],
)

def _helm_command_output_impl(ctx):
    cmd = ctx.attr.command[0]
    install_info = cmd[HelmInstallInfo]
    args_file = install_info.args_file
    executable = cmd[DefaultInfo].files_to_run.executable

    all_runfiles = cmd[DefaultInfo].default_runfiles.files.to_list()

    manifest = ctx.actions.declare_file(ctx.label.name + ".runfiles_manifest")
    manifest_lines = []
    for f in all_runfiles:
        manifest_lines.append("{} {}".format(
            _rlocationpath(f, ctx.workspace_name),
            f.path,
        ))
    ctx.actions.write(manifest, "\n".join(manifest_lines) + "\n")

    output = ctx.actions.declare_file(ctx.label.name + ".txt")

    ctx.actions.run_shell(
        inputs = all_runfiles + [manifest],
        outputs = [output],
        command = (
            'RUNFILES_MANIFEST_FILE="{manifest}" ' +
            'RULES_HELM_HELM_RUNNER_ARGS_FILE="{args_rloc}" ' +
            '"{executable}" > "{output}" 2>&1 || true'
        ).format(
            manifest = manifest.path,
            args_rloc = _rlocationpath(args_file, ctx.workspace_name),
            executable = executable.path,
            output = output.path,
        ),
    )

    return [DefaultInfo(files = depset([output]))]

helm_command_output = rule(
    doc = "Run a helm_command target (transitioned to the plugin toolchain) and capture its output to a file.",
    implementation = _helm_command_output_impl,
    attrs = {
        "command": attr.label(
            doc = "A helm_command target to run.",
            mandatory = True,
            providers = [HelmInstallInfo],
            cfg = _helm_toolchain_transition,
        ),
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
)

def _helm_command_output_test_impl(ctx):
    output_file = ctx.attr.output.files.to_list()[0]

    test_runner = ctx.actions.declare_file(ctx.label.name)
    ctx.actions.symlink(
        output = test_runner,
        target_file = ctx.executable._test_runner,
        is_executable = True,
    )

    runfiles = ctx.runfiles(files = [output_file])
    runfiles = runfiles.merge(ctx.attr._test_runner[DefaultInfo].default_runfiles)

    return [
        DefaultInfo(
            executable = test_runner,
            runfiles = runfiles,
        ),
        testing.TestEnvironment(
            environment = {
                "EXPECTED_PATTERN": ctx.attr.expected_pattern,
                "HELM_COMMAND_OUTPUT": _rlocationpath(output_file, ctx.workspace_name),
            },
        ),
    ]

helm_command_output_test = rule(
    doc = "Test that a helm_command output file matches an expected regex pattern.",
    implementation = _helm_command_output_test_impl,
    test = True,
    attrs = {
        "expected_pattern": attr.string(
            doc = "Regex pattern expected in the command output.",
            mandatory = True,
        ),
        "output": attr.label(
            doc = "A helm_command_output target whose output file to test.",
            mandatory = True,
        ),
        "_test_runner": attr.label(
            cfg = "exec",
            executable = True,
            default = Label("//tests/command/helm_command_output_test"),
        ),
    },
)

"""# Helm settings

Definitions for all `@rules_helm//helm` settings
"""

load(
    "@bazel_skylib//rules:common_settings.bzl",
    "bool_flag",
    "string_flag",
)
load("//helm/private:versions.bzl", "DEFAULT_HELM_VERSION", "HELM_VERSIONS")

def lint_default_strict():
    """A flag to control whether or not `helm_lint_*` rules default `-strict` to `True`
    """
    bool_flag(
        name = "lint_default_strict",
        build_setting_default = True,
    )

def lint_promote_info():
    """A flag to control whether `helm_lint_*` rules promote `[INFO]` diagnostics to errors."""
    bool_flag(
        name = "lint_promote_info",
        build_setting_default = False,
    )

def version(name = "version"):
    """The target version of helm"""
    string_flag(
        name = name,
        values = HELM_VERSIONS.keys(),
        build_setting_default = DEFAULT_HELM_VERSION,
    )

    for ver in HELM_VERSIONS.keys():
        native.config_setting(
            name = "{}_{}".format(name, ver),
            flag_values = {str(Label("//helm/settings:{}".format(name))): ver},
        )

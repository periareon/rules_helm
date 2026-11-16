"""# helm_plugin rule."""

load(
    "@rules_helm//helm:helm_plugin.bzl",
    _helm_plugin = "helm_plugin",
)

helm_plugin = _helm_plugin

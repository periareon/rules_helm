"""# helm_command rules."""

load(
    "@rules_helm//helm:helm_command.bzl",
    _helm_command = "helm_command",
)

helm_command = _helm_command

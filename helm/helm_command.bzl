"""# helm_command rules."""

load(
    "//helm/private:command.bzl",
    _helm_command = "helm_command",
)

helm_command = _helm_command

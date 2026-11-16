"""# helm_toolchain rule."""

load(
    "@rules_helm//helm:helm_toolchain.bzl",
    _helm_toolchain = "helm_toolchain",
)

helm_toolchain = _helm_toolchain

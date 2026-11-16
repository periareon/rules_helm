"""# helm_package rule."""

load(
    "@rules_helm//helm:helm_package.bzl",
    _helm_package = "helm_package",
)

helm_package = _helm_package

"""# helm_import rules."""

load(
    "@rules_helm//helm:helm_import.bzl",
    _helm_import = "helm_import",
    _helm_import_repository = "helm_import_repository",
)

helm_import = _helm_import
helm_import_repository = _helm_import_repository

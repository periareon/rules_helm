"""# helm_lint rules."""

load(
    "@rules_helm//helm:helm_lint.bzl",
    _helm_lint_aspect = "helm_lint_aspect",
    _helm_lint_test = "helm_lint_test",
)

helm_lint_aspect = _helm_lint_aspect
helm_lint_test = _helm_lint_test

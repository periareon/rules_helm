"""# helm_lint rules."""

load(
    "//helm/private:lint.bzl",
    _helm_lint_aspect = "helm_lint_aspect",
    _helm_lint_test = "helm_lint_test",
)

helm_lint_aspect = _helm_lint_aspect
helm_lint_test = _helm_lint_test

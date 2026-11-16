"""# helm_chart rule."""

load(
    "@rules_helm//helm:helm_chart.bzl",
    _helm_chart = "helm_chart",
)

helm_chart = _helm_chart

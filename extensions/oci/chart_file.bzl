"""# chart_file rules."""

load(
    "@rules_helm//helm:chart_file.bzl",
    _chart_content = "chart_content",
    _chart_file = "chart_file",
)

chart_content = _chart_content
chart_file = _chart_file

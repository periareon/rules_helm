"""# helm_template rules."""

load(
    "//helm/private:template.bzl",
    _helm_template = "helm_template",
    _helm_template_test = "helm_template_test",
)

helm_template = _helm_template
helm_template_test = _helm_template_test

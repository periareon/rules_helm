"""# helm_package rule."""

load(
    "//helm/private:package.bzl",
    _helm_package = "helm_package",
)

helm_package = _helm_package

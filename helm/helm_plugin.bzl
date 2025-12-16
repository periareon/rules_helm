"""# helm_plugin rule."""

load(
    "//helm/private:toolchain.bzl",
    _helm_plugin = "helm_plugin",
)

helm_plugin = _helm_plugin

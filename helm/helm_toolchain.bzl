"""# helm_toolchain rule."""

load(
    "//helm/private:toolchain.bzl",
    _helm_toolchain = "helm_toolchain",
)

helm_toolchain = _helm_toolchain

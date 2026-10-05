"""# kubectl_toolchain rules."""

load(
    "//k8s/private:kubectl_toolchain.bzl",
    _kubectl_toolchain = "kubectl_toolchain",
)

kubectl_toolchain = _kubectl_toolchain

"""# Bazel rules for Kubernetes tooling.

Rules for the tools that sit next to Helm when operating a cluster. Today this
is `kubectl`, fetched hermetically so `helm_install` / `helm_upgrade` failures
can be debugged with `bazel run @kubectl//:kubectl -- ...` without a locally
installed copy.
"""

load(
    ":kubectl_toolchain.bzl",
    _kubectl_toolchain = "kubectl_toolchain",
)

kubectl_toolchain = _kubectl_toolchain

"""Bzlmod test extensions"""

load("//tests:test_deps.bzl", "helm_test_deps")

def _helm_test_impl(module_ctx):
    helm_test_deps()

    # Every repository declared above pins a checksum, so the extension's
    # result is fully determined by its inputs and need not be recorded in
    # the lockfile.
    return module_ctx.extension_metadata(
        reproducible = True,
    )

helm_test = module_extension(
    implementation = _helm_test_impl,
)

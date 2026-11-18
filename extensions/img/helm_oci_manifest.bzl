"""# helm_oci_manifest macro."""

load(
    "//private:oci_manifest.bzl",
    _helm_oci_manifest = "helm_oci_manifest",
)

helm_oci_manifest = _helm_oci_manifest

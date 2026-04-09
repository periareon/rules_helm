"""# helm_oci_digest rules."""

load(
    "//helm/private:oci_digest.bzl",
    _HelmOCIDigestInfo = "HelmOCIDigestInfo",
    _helm_oci_digest = "helm_oci_digest",
)

helm_oci_digest = _helm_oci_digest
HelmOCIDigestInfo = _HelmOCIDigestInfo

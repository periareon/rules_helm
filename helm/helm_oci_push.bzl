"""# helm_oci_push rules."""

load(
    "//helm/private:oci_push.bzl",
    _helm_oci_push = "helm_oci_push",
)

helm_oci_push = _helm_oci_push

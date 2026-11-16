"""# helm_oci_image rule."""

load(
    "//private:image.bzl",
    _helm_oci_image = "helm_oci_image",
)

helm_oci_image = _helm_oci_image

"""# helm_image rule and HelmImageInfo provider."""

load(
    "@rules_helm//helm:helm_image.bzl",
    _HelmImageInfo = "HelmImageInfo",
    _helm_image = "helm_image",
)

HelmImageInfo = _HelmImageInfo
helm_image = _helm_image

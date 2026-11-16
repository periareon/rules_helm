"""# HelmPackageInfo provider"""

load(
    "@rules_helm//helm:helm_package_info.bzl",
    _HelmPackageInfo = "HelmPackageInfo",
)

HelmPackageInfo = _HelmPackageInfo

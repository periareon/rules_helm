"""# HelmPackageInfo provider"""

load(
    "//helm/private:providers.bzl",
    _HelmPackageInfo = "HelmPackageInfo",
)

HelmPackageInfo = _HelmPackageInfo

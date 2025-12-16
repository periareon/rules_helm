"""# helm_install rules."""

load(
    "//helm/private:install.bzl",
    _helm_install = "helm_install",
    _helm_uninstall = "helm_uninstall",
    _helm_upgrade = "helm_upgrade",
)

helm_install = _helm_install
helm_uninstall = _helm_uninstall
helm_upgrade = _helm_upgrade

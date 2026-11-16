"""# helm_push rules."""

load(
    "@rules_helm//helm:helm_push.bzl",
    _helm_push = "helm_push",
    _helm_push_images = "helm_push_images",
    _helm_push_registry = "helm_push_registry",
)

helm_push = _helm_push
helm_push_images = _helm_push_images
helm_push_registry = _helm_push_registry

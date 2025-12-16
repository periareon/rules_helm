"""# helm_push rules."""

load(
    "//helm/private:registry.bzl",
    _helm_push = "helm_push",
    _helm_push_images = "helm_push_images",
)

helm_push = _helm_push
helm_push_images = _helm_push_images
helm_push_registry = _helm_push  # Alias for backwards compatibility

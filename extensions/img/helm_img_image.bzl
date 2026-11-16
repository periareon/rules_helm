"""# helm_img_image rule."""

load(
    "//private:image.bzl",
    _helm_img_image = "helm_img_image",
)

helm_img_image = _helm_img_image

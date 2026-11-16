"""rules_helm provider definitions"""

HelmImageInfo = provider(
    doc = """\
A container image a helm chart refers to.

This is the contract between `rules_helm` and the rules that build images.
`rules_helm` only reads it: the chart's `values.yaml` has `{@label}` style
references replaced with `repository@digest`, and `pusher` is run before the
chart is installed or pushed. Any rule may provide it. `rules_helm` adapts
`oci_push`, `image_push` and `image_import` targets itself and the companion
modules (`rules_helm_img`, `rules_helm_oci`) provide it from their image
rules' own providers.
""",
    fields = {
        "aliases": "list[Label]: Other labels values may use to refer to the image.",
        "label": "Label: The label values use to refer to the image, e.g. `{@//app:image.push}`.",
        "manifest": "File: The raw OCI manifest or index, byte for byte what is pushed or was pulled. Its sha256 is the image digest.",
        "pusher": "File (optional): An executable that pushes the image. `None` for pulled images, which are referenced but never pushed.",
        "repository": "File: A single line, `<registry>/<repository>`, with no scheme.",
        "runfiles": "runfiles: Everything `pusher` needs at run time.",
        "tags": "File (optional): The remote tags, one per line.",
    },
)

HelmPackageInfo = provider(
    doc = "A provider for helm packages",
    fields = {
        "chart": "File: The result of `helm package`",
        "images": "list[HelmImageInfo]: The images bundled into the chart",
        "metadata": "File: A json encoded file containing metadata about the helm chart",
    },
)

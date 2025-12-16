"""rules_helm provider definitions"""

HelmPackageInfo = provider(
    doc = "A provider for helm packages",
    fields = {
        "chart": "File: The result of `helm package`",
        "images": "list[Target]: A list of [@rules_oci//oci:defs.bzl%oci_push](https://github.com/bazel-contrib/rules_oci/blob/main/docs/push.md#oci_push_rule-remote_tags) or [@rules_img//img:push.bzl%image_push](https://github.com/bazel-contrib/rules_img) targets",
        "metadata": "File: A json encoded file containing metadata about the helm chart",
    },
)

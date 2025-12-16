"""Utilities for container images"""

ImagePushRepositoryInfo = provider(
    doc = "Repository and image information for a given oci_push or image_push target",
    fields = {
        "manifest_file": "File (optional): The manifest JSON file for rules_img images",
        "oci_layout": "File (optional): The OCI layout directory for rules_oci images (contains index.json)",
        "remote_tags_file": "File (optional): The file containing remote tags (one per line) used for the push target",
        "repository_file": "File: The file containing the repository path for the push target",
    },
)

def _image_push_repository_aspect_impl(target, ctx):
    # Handle rules_img image_push
    if hasattr(ctx.rule.attr, "registry") and ctx.rule.attr.registry:
        # rules_img uses registry + repository attributes
        if hasattr(ctx.rule.attr, "repository") and ctx.rule.attr.repository:
            # Combine registry and repository for full repository path
            registry = ctx.rule.attr.registry
            repo = ctx.rule.attr.repository

            # Remove protocol from registry if present
            registry_clean = registry.replace("https://", "").replace("http://", "")
            full_repo = "{}/{}".format(registry_clean, repo)

            output = ctx.actions.declare_file("{}.rules_helm.repository.txt".format(target.label.name))
            ctx.actions.write(
                output = output,
                content = full_repo,
            )
        else:
            fail("image_push target {} must have a `repository` attribute".format(target.label))

        # rules_img image_push has 'image' attribute pointing to image_manifest
        if not hasattr(ctx.rule.attr, "image") or not ctx.rule.attr.image:
            fail("image_push target {} must have an `image` attribute".format(target.label))

        # Get the image file from the image attribute
        image_file = None
        if hasattr(ctx.rule.files, "image") and ctx.rule.files.image:
            image_file = ctx.rule.files.image[0]
        elif hasattr(ctx.rule.file, "image") and ctx.rule.file.image:
            image_file = ctx.rule.file.image
        else:
            fail("image_push target {} `image` attribute must provide files".format(target.label))

        # rules_img uses tags attribute (list of strings) instead of remote_tags file
        remote_tags_file = None
        if hasattr(ctx.rule.attr, "tags") and ctx.rule.attr.tags:
            # Write tags to a file for consistency with rules_oci
            tags_output = ctx.actions.declare_file("{}.rules_helm.tags.txt".format(target.label.name))
            ctx.actions.write(
                output = tags_output,
                content = "\n".join(ctx.rule.attr.tags),
            )
            remote_tags_file = tags_output

        return [ImagePushRepositoryInfo(
            repository_file = output,
            manifest_file = image_file,
            oci_layout = None,
            remote_tags_file = remote_tags_file,
        )]

    # Handle rules_oci oci_push
    if hasattr(ctx.rule.attr, "repository") and ctx.rule.attr.repository:
        output = ctx.actions.declare_file("{}.rules_helm.repository.txt".format(target.label.name))
        ctx.actions.write(
            output = output,
            content = ctx.rule.attr.repository,
        )
    elif hasattr(ctx.rule.file, "repository_file") and ctx.rule.file.repository_file:
        output = ctx.rule.file.repository_file
    else:
        fail("oci_push/image_push target {} must have a `repository` attribute or a `repository_file` file".format(
            target.label,
        ))

    if not hasattr(ctx.rule.file, "image"):
        fail("oci_push/image_push target {} must have an `image` attribute".format(
            target.label,
        ))

    remote_tags_file = None
    if hasattr(ctx.rule.file, "remote_tags") and ctx.rule.file.remote_tags:
        remote_tags_file = ctx.rule.file.remote_tags

    return [ImagePushRepositoryInfo(
        repository_file = output,
        oci_layout = ctx.rule.file.image,
        manifest_file = None,
        remote_tags_file = remote_tags_file,
    )]

# This aspect exists because rules_oci and rules_img don't provide a provider
# that cleanly publishes this information but for the helm rules, it's
# absolutely necessary that an image's repository and digest are knowable.
# If rules_oci/rules_img decide to define their own provider for this (which they should)
# then this should be deleted in favor of that.
image_push_repository_aspect = aspect(
    doc = "Provides the repository and image_root for a given oci_push or image_push target",
    implementation = _image_push_repository_aspect_impl,
)

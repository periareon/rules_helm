"""Bzlmod extensions"""

load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load(
    "//helm/private:repositories.bzl",
    "helm_host_alias_repository",
    "helm_toolchain_repository",
    "helm_toolchain_repository_hub",
)
load(
    "//helm/private:versions.bzl",
    "CONSTRAINTS",
    "DEFAULT_HELM_URL_TEMPLATES",
    "DEFAULT_HELM_VERSION",
    "HELM_VERSIONS",
)

def _find_modules(module_ctx):
    root = None
    rules_module = None
    for mod in module_ctx.modules:
        if mod.is_root:
            root = mod
        if mod.name == "rules_helm":
            rules_module = mod
    if root == None:
        root = rules_module
    if rules_module == None:
        fail("Unable to find rules_helm module")

    return root, rules_module

def _helm_impl(module_ctx):
    root_mod, rules_mod = _find_modules(module_ctx)

    toolchains = root_mod.tags.toolchain
    if not toolchains:
        toolchains = rules_mod.tags.toolchain

    host_tools = root_mod.tags.host_tools
    if not host_tools:
        host_tools = rules_mod.tags.host_tools

    for attrs in toolchains:
        if attrs.version not in HELM_VERSIONS:
            fail("Helm toolchain hub `{}` was given unsupported version `{}`. Try: {}".format(
                attrs.name,
                attrs.version,
                HELM_VERSIONS.keys(),
            ))
        available = HELM_VERSIONS[attrs.version]
        toolchain_names = []
        toolchain_labels = {}
        target_compatible_with = {}
        exec_compatible_with = {}

        for platform, integrity in available.items():
            if platform.startswith("windows"):
                compression = "zip"
            else:
                compression = "tar.gz"

            # The URLs for linux-i386 artifacts are actually published under
            # a different name. The check below accounts for this.
            # https://github.com/abrisco/rules_helm/issues/76
            url_platform = platform
            if url_platform == "linux-i386":
                url_platform = "linux-386"

            toolchain_repo_name = "{}__{}_{}_bin".format(attrs.name, attrs.version, platform.replace("-", "_"))

            # Create the hub-specific binary repository
            maybe(
                helm_toolchain_repository,
                name = toolchain_repo_name,
                urls = [
                    template.replace(
                        "{version}",
                        attrs.version,
                    ).replace(
                        "{platform}",
                        url_platform,
                    ).replace(
                        "{compression}",
                        compression,
                    )
                    for template in attrs.helm_url_templates
                ],
                integrity = integrity,
                strip_prefix = url_platform,
                plugins = attrs.plugins,
                platform = platform,
            )

            toolchain_names.append(toolchain_repo_name)
            toolchain_labels[toolchain_repo_name] = "@{}".format(toolchain_repo_name)
            target_compatible_with[toolchain_repo_name] = []
            exec_compatible_with[toolchain_repo_name] = CONSTRAINTS[platform]

        maybe(
            helm_toolchain_repository_hub,
            name = attrs.name,
            toolchain_labels = toolchain_labels,
            toolchain_names = toolchain_names,
            exec_compatible_with = exec_compatible_with,
            target_compatible_with = target_compatible_with,
        )

    # Process host_tools tags
    for host_tools_attrs in host_tools:
        maybe(
            helm_host_alias_repository,
            name = host_tools_attrs.name,
        )

    return module_ctx.extension_metadata(
        reproducible = True,
    )

_toolchain = tag_class(
    doc = """\
An extension for defining a `helm_toolchain` from a download archive.

An example of defining and registering toolchains:

```python
helm = use_extension("@rules_helm//helm:extensions.bzl", "helm")
helm.toolchain(
    name = "helm_toolchains",
    version = "3.14.4",
)
use_repo(helm, "helm_toolchains")

register_toolchains(
    "@helm_toolchains//:all",
)
```
""",
    attrs = {
        "helm_url_templates": attr.string_list(
            doc = (
                "A url template used to download helm. The template can contain the following " +
                "format strings `{platform}` for the helm platform, `{version}` for the helm " +
                "version, and `{compression}` for the archive type containing the helm binary."
            ),
            default = DEFAULT_HELM_URL_TEMPLATES,
        ),
        "name": attr.string(
            doc = "The name of the toolchain hub repository.",
            default = "helm_toolchains",
        ),
        "plugins": attr.string_list(
            doc = "A list of plugins to add to the generated toolchain.",
            default = [],
        ),
        "version": attr.string(
            doc = "The version of helm to download for the toolchain.",
            default = DEFAULT_HELM_VERSION,
        ),
    },
)

_host_tools = tag_class(
    doc = """\
An extension for creating a host alias repository that provides a shorter name for the host platform's helm binary.

An example of defining and using host tools:

```python
helm = use_extension("@rules_helm//helm:extensions.bzl", "helm")
helm.host_tools(name = "helm")
use_repo(helm, "helm")

# Then you can use @helm//:helm in your BUILD files
```
""",
    attrs = {
        "name": attr.string(
            doc = "The name of the host alias repository.",
            default = "helm",
        ),
    },
)

helm = module_extension(
    implementation = _helm_impl,
    tag_classes = {
        "host_tools": _host_tools,
        "toolchain": _toolchain,
    },
)

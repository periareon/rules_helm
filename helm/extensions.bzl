"""Bzlmod extensions"""

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

    host_tools = root_mod.tags.host_tools
    if not host_tools:
        host_tools = rules_mod.tags.host_tools

    toolchain_names = []
    toolchain_labels = {}
    target_compatible_with = {}
    exec_compatible_with = {}
    target_settings = {}

    for version, available in HELM_VERSIONS.items():
        for platform, integrity in available.items():
            if platform.startswith("windows"):
                compression = "zip"
            else:
                compression = "tar.gz"

            # The URLs for linux-i386 artifacts are actually published under
            # a different name. The check below accounts for this.
            # https://github.com/periareon/rules_helm/issues/76
            url_platform = platform
            if url_platform == "linux-i386":
                url_platform = "linux-386"

            toolchain_repo_name = "helm_toolchains__{}_{}_bin".format(version, platform.replace("-", "_"))

            helm_toolchain_repository(
                name = toolchain_repo_name,
                urls = [
                    template.replace(
                        "{version}",
                        version,
                    ).replace(
                        "{platform}",
                        url_platform,
                    ).replace(
                        "{compression}",
                        compression,
                    )
                    for template in DEFAULT_HELM_URL_TEMPLATES
                ],
                integrity = integrity,
                strip_prefix = url_platform,
                platform = platform,
            )

            toolchain_names.append(toolchain_repo_name)
            toolchain_labels[toolchain_repo_name] = "@{}".format(toolchain_repo_name)
            target_compatible_with[toolchain_repo_name] = []
            exec_compatible_with[toolchain_repo_name] = CONSTRAINTS[platform]
            target_settings[toolchain_repo_name] = ["@rules_helm//helm/settings:version_{}".format(version)]

    helm_toolchain_repository_hub(
        name = "helm_toolchains",
        toolchain_labels = toolchain_labels,
        toolchain_names = toolchain_names,
        exec_compatible_with = exec_compatible_with,
        target_compatible_with = target_compatible_with,
        target_settings = target_settings,
    )

    for host_tools_attrs in host_tools:
        helm_host_alias_repository(
            name = host_tools_attrs.name,
            toolchain_repo_prefix = "helm_toolchains__{}".format(host_tools_attrs.version),
        )

    return module_ctx.extension_metadata(
        reproducible = True,
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
        "version": attr.string(
            doc = "The version of helm to use for host tools.",
            default = DEFAULT_HELM_VERSION,
        ),
    },
)

helm = module_extension(
    implementation = _helm_impl,
    tag_classes = {
        "host_tools": _host_tools,
    },
)

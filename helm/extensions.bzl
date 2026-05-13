"""Bzlmod extensions"""

load(
    "//helm/private:repositories.bzl",
    "helm_host_alias_repository",
    "helm_plugin_repository",
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

    plugins = root_mod.tags.plugin

    # Create plugin repos and build a map of platform -> plugin labels.
    platform_plugins = {}
    for plugin_attrs in plugins:
        for platform, integrity in plugin_attrs.integrity.items():
            plugin_repo_name = "helm_plugin_{}_{}".format(
                plugin_attrs.name,
                platform.replace("-", "_"),
            )

            helm_plugin_repository(
                name = plugin_repo_name,
                plugin_name = plugin_attrs.name,
                urls = [
                    template.replace("{version}", plugin_attrs.version)
                    for template in plugin_attrs.url_templates[platform]
                ],
                integrity = integrity,
                strip_prefix = plugin_attrs.strip_prefix,
                yaml = plugin_attrs.yaml,
            )

            if platform not in platform_plugins:
                platform_plugins[platform] = []
            platform_plugins[platform].append(
                "@{}//:{}".format(plugin_repo_name, plugin_attrs.name),
            )

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
                plugins = platform_plugins.get(platform, []),
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

_plugin = tag_class(
    doc = """\
An extension tag for declaring Helm plugins to include in all toolchains.

Plugins are downloaded per-platform and wired into each generated helm_toolchain.
Only platforms listed in `integrity` (and `url_templates`) will receive the plugin.

An example of declaring the helm-diff plugin:

```python
helm = use_extension("@rules_helm//helm:extensions.bzl", "helm")
helm.host_tools()
helm.plugin(
    name = "diff",
    version = "3.15.5",
    strip_prefix = "diff",
    url_templates = {
        "darwin-arm64": ["https://github.com/databus23/helm-diff/releases/download/v{version}/helm-diff-macos-arm64.tgz"],
        "darwin-amd64": ["https://github.com/databus23/helm-diff/releases/download/v{version}/helm-diff-macos-amd64.tgz"],
        "linux-amd64": ["https://github.com/databus23/helm-diff/releases/download/v{version}/helm-diff-linux-amd64.tgz"],
        "linux-arm64": ["https://github.com/databus23/helm-diff/releases/download/v{version}/helm-diff-linux-arm64.tgz"],
    },
    integrity = {
        "darwin-arm64": "sha256-KJmZ7wY3gAcWFzK5R9+TfQlaRfEXzJ7hDNRC8NgIDog=",
        "linux-amd64": "sha256-ToJjCrKyMxfAOeezsWYF95qKwPPSKHPg1G6pzZgN2o4=",
        "linux-arm64": "sha256-4tu/93Bo2T7VYgYj6oHyTYah7UQAuRmE1jgvSAEfaaM=",
    },
)
```
""",
    attrs = {
        "integrity": attr.string_dict(
            doc = "A mapping of helm platform name to integrity hash. Only platforms listed here will receive the plugin.",
            mandatory = True,
        ),
        "name": attr.string(
            doc = "The name of the plugin.",
            mandatory = True,
        ),
        "strip_prefix": attr.string(
            doc = "A directory prefix to strip from the extracted plugin archive.",
        ),
        "url_templates": attr.string_list_dict(
            doc = "Mapping of helm platform name to a list of URL templates for downloading the plugin on that platform. Only `{version}` is substituted; spell the platform name into the URL string directly. Every key in `integrity` must have a matching entry here.",
            mandatory = True,
        ),
        "version": attr.string(
            doc = "The version of the plugin to download.",
            mandatory = True,
        ),
        "yaml": attr.string(
            doc = "Relative path to plugin.yaml within the extracted archive (after strip_prefix).",
            default = "plugin.yaml",
        ),
    },
)

helm = module_extension(
    implementation = _helm_impl,
    tag_classes = {
        "host_tools": _host_tools,
        "plugin": _plugin,
    },
)

"""Bzlmod extensions for Kubernetes tooling"""

# buildifier: disable=bzl-visibility
load("//helm/private:extension_utils.bzl", "find_modules")

# buildifier: disable=bzl-visibility
load("//helm/private:repositories.bzl", "helm_toolchain_repository_hub")
load(
    "//k8s/private:kubectl_repositories.bzl",
    "kubectl_host_alias_repository",
    "kubectl_toolchain_repository",
)
load(
    "//k8s/private:kubectl_versions.bzl",
    "DEFAULT_KUBECTL_VERSION",
    "KUBECTL_PLATFORMS",
    "KUBECTL_VERSIONS",
    "kubectl_urls",
)

_HUB_NAME = "kubectl_toolchains"

def _toolchain_repo_prefix(version):
    return "{}__{}".format(_HUB_NAME, version)

def _toolchain_repo_name(version, platform):
    return "{}_{}_bin".format(_toolchain_repo_prefix(version), platform.replace("-", "_"))

def _fetch_kubectl_checksums(module_ctx, version):
    """Download the upstream `.sha256` files for a kubectl release.

    Args:
        module_ctx (module_ctx): The module extension context.
        version (str): The kubectl version, without a leading `v`.

    Returns:
        dict: A mapping of platform name to hex-encoded sha256 digest.
    """
    checksums = {}
    for platform in KUBECTL_PLATFORMS:
        urls = [url + ".sha256" for url in kubectl_urls(version, platform)]
        output = "kubectl-{}-{}.sha256".format(version, platform)
        result = module_ctx.download(
            urls,
            output = output,
            allow_fail = True,
        )
        if not result.success:
            fail((
                "Failed to download the kubectl checksum for version `{}` ({}). " +
                "Is `{}` a published kubectl release? Tried: {}"
            ).format(version, platform, version, ", ".join(urls)))

        # The file holds the hex digest, optionally followed by a file name.
        content = module_ctx.read(output).strip()
        fields = [f for f in content.replace("\t", " ").replace("\n", " ").split(" ") if f]
        if not fields or len(fields[0]) != 64:
            fail("Unexpected content in kubectl checksum file {}: {}".format(urls[0], content))

        checksums[platform] = fields[0]

    return checksums

def _k8s_impl(module_ctx):
    root_mod, rules_mod = find_modules(module_ctx)

    kubectl_tags = root_mod.tags.kubectl
    if not kubectl_tags:
        kubectl_tags = rules_mod.tags.kubectl

    # Checksums persisted in the lockfile by a previous evaluation (Bazel 8.5+).
    facts = getattr(module_ctx, "facts", {})
    used_facts = {}

    # The registered toolchains serve a single version: the one requested by the
    # root module's first `kubectl` tag.
    toolchain_version = kubectl_tags[0].version if kubectl_tags else DEFAULT_KUBECTL_VERSION

    versions = {toolchain_version: None}
    for tag in kubectl_tags:
        versions[tag.version] = None

    checksums_by_version = {}
    for version in versions:
        checksums = KUBECTL_VERSIONS.get(version)
        if checksums == None:
            checksums = facts.get(version)
        if checksums == None:
            checksums = _fetch_kubectl_checksums(module_ctx, version)

        if version not in KUBECTL_VERSIONS:
            used_facts[version] = checksums

        checksums_by_version[version] = checksums

        for platform, sha256 in checksums.items():
            if platform not in KUBECTL_PLATFORMS:
                continue

            kubectl_toolchain_repository(
                name = _toolchain_repo_name(version, platform),
                urls = kubectl_urls(version, platform),
                sha256 = sha256,
                platform = platform,
            )

    # --- Toolchain hub ---

    toolchain_names = []
    toolchain_labels = {}
    exec_compatible_with = {}
    target_compatible_with = {}

    for platform in checksums_by_version[toolchain_version]:
        if platform not in KUBECTL_PLATFORMS:
            continue

        toolchain_repo_name = _toolchain_repo_name(toolchain_version, platform)
        toolchain_names.append(toolchain_repo_name)
        toolchain_labels[toolchain_repo_name] = "@{}".format(toolchain_repo_name)
        exec_compatible_with[toolchain_repo_name] = KUBECTL_PLATFORMS[platform].constraints
        target_compatible_with[toolchain_repo_name] = []

    helm_toolchain_repository_hub(
        name = _HUB_NAME,
        toolchain_labels = toolchain_labels,
        toolchain_names = toolchain_names,
        exec_compatible_with = exec_compatible_with,
        target_compatible_with = target_compatible_with,
        target_settings = {},
        toolchain_type = Label("//k8s:kubectl_toolchain_type"),
    )

    # --- Host aliases ---

    for tag in kubectl_tags:
        kubectl_host_alias_repository(
            name = tag.name,
            toolchain_repo_prefix = _toolchain_repo_prefix(tag.version),
            version = tag.version,
        )

    kwargs = {"reproducible": True}

    # Bazel 8.5+ persists facts in the lockfile so later evaluations (and
    # airgapped builds) never re-download the checksum files.
    if hasattr(module_ctx, "facts"):
        kwargs["facts"] = used_facts

    return module_ctx.extension_metadata(**kwargs)

_kubectl = tag_class(
    doc = """\
Fetch a `kubectl` binary for the host platform and register toolchains for it.

Each tag creates a host alias repository (default `@kubectl`) that exposes the \
binary as `@{name}//:kubectl`, which is the quickest way to inspect a cluster \
after a `helm_install` / `helm_upgrade`:

```python
k8s = use_extension("@rules_helm//k8s:extensions.bzl", "k8s")
k8s.kubectl()
use_repo(k8s, "kubectl", "kubectl_toolchains")
register_toolchains("@kubectl_toolchains//:all")
```

```bash
bazel run @kubectl//:kubectl -- get pods --namespace my-release
bazel run @kubectl//:kubectl -- describe deployment my-release
bazel run @kubectl//:kubectl -- logs deployment/my-release --tail 100
```

The toolchains in `@kubectl_toolchains` serve the version requested by the root \
module's first `kubectl` tag (or the default when the root module has none).

### Versions

`rules_helm` ships checksums for a single default version. Requesting any \
other version makes the extension download the upstream `.sha256` files for \
that release while it is evaluated. On Bazel 8.5 and newer the digests are then stored \
as facts in `MODULE.bazel.lock`, so the lookup only happens once per version \
and airgapped builds work from the lockfile. Older Bazel versions repeat the \
lookup whenever the extension is re-evaluated.

```python
k8s.kubectl(version = "1.36.5")
```
""",
    attrs = {
        "name": attr.string(
            doc = "The name of the host alias repository.",
            default = "kubectl",
        ),
        "version": attr.string(
            doc = "The version of kubectl to fetch, without a leading `v`.",
            default = DEFAULT_KUBECTL_VERSION,
        ),
    },
)

k8s = module_extension(
    doc = "Module extension for fetching Kubernetes tooling such as `kubectl`.",
    implementation = _k8s_impl,
    tag_classes = {
        "kubectl": _kubectl,
    },
)

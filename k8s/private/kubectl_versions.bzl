"""Constants for accessing kubectl binaries"""

DEFAULT_KUBECTL_VERSION = "1.37.1"

# Format arguments are `{version}`, `{os}`, `{arch}` and `{ext}` (`.exe` on windows).
KUBECTL_URL_TEMPLATES = [
    "https://dl.k8s.io/release/v{version}/bin/{os}/{arch}/kubectl{ext}",
]

def _platform(os, arch, constraints):
    return struct(
        os = os,
        arch = arch,
        constraints = constraints,
    )

# Platforms kubectl is published for, keyed by the `{os}-{arch}` name used in
# repository names. Keep in sync with `KUBECTL_PLATFORMS` in
# `tools/fetch_shas/fetch_shas.go`.
KUBECTL_PLATFORMS = {
    "darwin-amd64": _platform("darwin", "amd64", ["@platforms//os:macos", "@platforms//cpu:x86_64"]),
    "darwin-arm64": _platform("darwin", "arm64", ["@platforms//os:macos", "@platforms//cpu:aarch64"]),
    "linux-386": _platform("linux", "386", ["@platforms//os:linux", "@platforms//cpu:i386"]),
    "linux-amd64": _platform("linux", "amd64", ["@platforms//os:linux", "@platforms//cpu:x86_64"]),
    "linux-arm": _platform("linux", "arm", ["@platforms//os:linux", "@platforms//cpu:arm"]),
    "linux-arm64": _platform("linux", "arm64", ["@platforms//os:linux", "@platforms//cpu:aarch64"]),
    "linux-ppc64le": _platform("linux", "ppc64le", ["@platforms//os:linux", "@platforms//cpu:ppc64le"]),
    "linux-s390x": _platform("linux", "s390x", ["@platforms//os:linux", "@platforms//cpu:s390x"]),
    "windows-amd64": _platform("windows", "amd64", ["@platforms//os:windows", "@platforms//cpu:x86_64"]),
    "windows-arm64": _platform("windows", "arm64", ["@platforms//os:windows", "@platforms//cpu:aarch64"]),
}

def kubectl_urls(version, platform):
    """Return the download URLs for a kubectl binary.

    Args:
        version (str): The kubectl version, without a leading `v`.
        platform (str): A key of `KUBECTL_PLATFORMS`.

    Returns:
        list: URLs to try in order.
    """
    info = KUBECTL_PLATFORMS[platform]
    ext = ".exe" if info.os == "windows" else ""
    return [
        template.replace("{version}", version).replace("{os}", info.os).replace("{arch}", info.arch).replace("{ext}", ext)
        for template in KUBECTL_URL_TEMPLATES
    ]

# Hex-encoded sha256 digests, as published upstream. This table is manually
# updated using the following command:
# ```
# bazel run //tools/fetch_shas -- -tool kubectl <version>
# ```
#
# Versions not listed here are resolved when the `k8s` module extension is
# evaluated and, on Bazel 8.5+, persisted as facts in `MODULE.bazel.lock`.
KUBECTL_VERSIONS = {
    "1.37.1": {
        "darwin-amd64": "6851381c486ff6edd691623e3d65c87cb9a5b02887ff8fbbb38d8a031b748387",
        "darwin-arm64": "fd65982c97ddad3106754b69ffa196d0e543aa591930ae52aed1adfb92f8c77f",
        "linux-386": "e0a491f328222aac3f3a7a1e9dafc9160ae0f839ec73c202c805da64b4eb0b02",
        "linux-amd64": "65691ff77eb6fa44c908b77a1082c9f092c3b9733b5cefabec0d1104890e21a8",
        "linux-arm": "8af0113a5b03b13b923f530bc4177479799dee2a0c188d15bef0ebef5d0c6d75",
        "linux-arm64": "ff749f4b78d9c4f1ec87307df9b50119ed819e2094aa9810cb9acffc3286c8c7",
        "linux-ppc64le": "50a33e7a7f0d1125099abbdba3c010a3cb497142f58ed8ea198949f738e79b82",
        "linux-s390x": "222798cd808e287cccd427718f9d76f7b3bff4e8601dca96b8bf5c371d3b59f6",
        "windows-amd64": "14b93c4916a6f37a06fbc1f46b0a1d2404c4f9741be09f00d6caf8af3b05f1d3",
        "windows-arm64": "1f0ce2ba3384a082ee846f74dc27f3877d7ecb03082ee3c0cd58c5fc027c2a1b",
    },
}

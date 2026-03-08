"""Dependencies for helm test/example targets"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("@rules_img//img:pull.bzl", img_pull = "pull")
load("@rules_oci//oci:pull.bzl", "oci_pull")
load("//helm:defs.bzl", "helm_import_repository")

_CM_HELM_PUSH_BUILD_CONTENT = """\
package(default_visibility = ["//visibility:public"])

exports_files(["plugin.yaml"])

filegroup(
    name = "data",
    srcs = glob(["bin/**"]),
)
"""

def helm_test_deps():
    """Helm test dependencies"""

    # Find this chart in the repository:
    maybe(
        helm_import_repository,
        name = "helm_test_deps__with_external_deps_redis",
        repository = "https://charts.bitnami.com/bitnami",
        chart_name = "redis",
        version = "21.2.5",
        sha256 = "4f70fc4c8caac66b21450581e29e3437cad401895d5ac0191e9e91f74ed8dc10",
    )

    # Directly download this chart from a HTTP URL:
    maybe(
        helm_import_repository,
        name = "helm_test_deps__with_external_deps_postgresql",
        url = "https://charts.bitnami.com/bitnami/postgresql-14.0.5.tgz",
        sha256 = "38d9b6657aa3b0cc16d190570dbaf96796e997d03a1665264dac9966343e4d1b",
    )

    # Directly download charts from an OCI URL:
    maybe(
        helm_import_repository,
        name = "helm_test_deps__with_external_deps_grafana",
        url = "oci://registry-1.docker.io/bitnamicharts/grafana:12.1.4",
        sha256 = "015f66a231a809557ab368d903f6762ba31ba2f7b3d0f890445be6e8f213cff1",
    )
    maybe(
        helm_import_repository,
        name = "helm_test_deps__with_external_deps_bank_vaults",
        sha256 = "9abd372c9d843b974d918442cd0e68c9669f57d8630566ce74dfaf63447c282a",
        url = "oci://ghcr.io/bank-vaults/helm-charts/vault-operator:1.23.0",
    )
    maybe(
        helm_import_repository,
        name = "helm_test_deps__with_external_deps_karpenter",
        sha256 = "6fb277a7659bd5c732f5e4f81f720ec147fefc51983863a7b14ac7914bdcca55",
        url = "oci://public.ecr.aws/karpenter/karpenter:1.9.0",
    )
    maybe(
        helm_import_repository,
        name = "helm_test_deps__with_external_deps_cert_manager",
        sha256 = "d0c202f57b8653eb957fb5b2f9472c1b11cf6b51acc5c777e4b824f7b5a9ea87",
        url = "oci://quay.io/jetstack/charts/cert-manager:1.19.4",
    )

    maybe(
        oci_pull,
        name = "rules_helm_test_oci_container_base",
        digest = "sha256:2042a492bcdd847a01cd7f119cd48caa180da696ed2aedd085001a78664407d6",
        image = "alpine",
    )

    maybe(
        img_pull,
        name = "rules_helm_test_img_container_base",
        digest = "sha256:2042a492bcdd847a01cd7f119cd48caa180da696ed2aedd085001a78664407d6",
        registry = "index.docker.io",
        repository = "library/alpine",
    )

    maybe(
        http_archive,
        name = "helm_cm_push_linux",
        urls = ["https://github.com/chartmuseum/helm-push/releases/download/v0.10.4/helm-push_0.10.4_linux_amd64.tar.gz"],
        integrity = "sha256-KfH3E2mbR+PJwY1gtQVffA6LzBIh1mOcBX54fgi2Vqg=",
        build_file_content = _CM_HELM_PUSH_BUILD_CONTENT,
    )

    maybe(
        http_archive,
        name = "helm_cm_push_macos",
        urls = ["https://github.com/chartmuseum/helm-push/releases/download/v0.10.4/helm-push_0.10.4_darwin_arm64.tar.gz"],
        integrity = "sha256-oKyCvUYCHt/LPcIj99ZaVP6PlpGPy7dgwTl/yo43SqI=",
        build_file_content = _CM_HELM_PUSH_BUILD_CONTENT,
    )

    maybe(
        http_archive,
        name = "helm_cm_push_windows",
        urls = ["https://github.com/chartmuseum/helm-push/releases/download/v0.10.4/helm-push_0.10.4_windows_amd64.tar.gz"],
        integrity = "sha256-aFkN3IJXd8TVlJ/NY3v2sZ4Rerp644e02u0HNqboELw=",
        build_file_content = _CM_HELM_PUSH_BUILD_CONTENT,
    )

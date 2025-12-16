"""Helm rules"""

load(":install.bzl", "helm_install", "helm_uninstall", "helm_upgrade")
load(":package.bzl", "helm_package")
load(":registry.bzl", "helm_push", "helm_push_images")

def helm_chart(
        *,
        name,
        chart = None,
        chart_json = None,
        crds = None,
        values = None,
        values_json = None,
        substitutions = {},
        templates = None,
        schema = None,
        files = [],
        images = [],
        deps = None,
        install_name = None,
        registry_url = None,
        login_url = None,
        push_cmd = None,
        helm_opts = [],
        install_opts = [],
        upgrade_opts = [],
        uninstall_opts = [],
        data = [],
        stamp = None,
        **kwargs):
    """Rules for producing a helm package and some convenience targets.

    | target | rule | condition |
    | --- | --- | --- |
    | `{name}` | [helm_package](#helm_package) | `None` |
    | `{name}.push_images` | [helm_push_images](#helm_push_images) | `None` |
    | `{name}.push_registry` | [helm_push](#helm_push) (`include_images = False`) | `registry_url` is defined. |
    | `{name}.push` | [helm_push](#helm_push) (`include_images = True`) | `registry_url` is defined. |
    | `{name}.install` | [helm_install](#helm_install) | `None` |
    | `{name}.uninstall` | [helm_uninstall](#helm_uninstall) | `None` |
    | `{name}.upgrade` | [helm_upgrade](#helm_upgrade) | `None` |

    Args:
        name (str): The name of the [helm_package](#helm_package) target.
        chart (str, optional): The path to the chart directory. Defaults to `Chart.yaml`.
        chart_json (str, optional): The json encoded contents of `Chart.yaml`.
        crds (list, optional): A list of crd files to include in the package.
        values (str, optional): The path to the values file. Defaults to `values.yaml`.
        values_json (str, optional): The json encoded contents of `values.yaml`.
        substitutions (dict, optional): A dictionary of substitutions to apply to `values.yaml`.
        templates (list, optional): A list of template files to include in the package.
        schema (str, optional): A JSON Schema file for values. Defaults to `values.schema.json`.
        files (list, optional): Files accessed in templates via the [`.Files` api](https://helm.sh/docs/chart_template_guide/accessing_files/).
        images (list, optional): A list of [oci_push](https://github.com/bazel-contrib/rules_oci/blob/main/docs/push.md#oci_push_rule-remote_tags) or [image_push](https://github.com/bazel-contrib/rules_img) targets
        deps (list, optional): A list of helm package dependencies.
        install_name (str, optional): The `helm install` name to use. `name` will be used if unset.
        registry_url (str, Optional): The registry url for the helm chart. `{name}.push_registry`
            is only defined when a value is passed here.
        login_url (str, optional): The registry url to log into for publishing helm charts.
        push_cmd (str, optional): An alternative command to `push` for publishing helm charts.
        helm_opts (list, optional): Additional options to pass to helm.
        install_opts (list, optional): Additional options to pass to `helm install`.
        uninstall_opts (list, optional): Additional options to pass to `helm uninstall`.
        upgrade_opts (list, optional): Additional options to pass to `helm upgrade`.
        data (list, optional): Additional runtime data to pass to the helm install, upgrade, and uninstall targets.
        stamp (int):  Whether to encode build information into the helm chart.
        **kwargs (dict): Additional keyword arguments for `helm_package`.
    """
    if chart_json == None and chart == None:
        chart = "Chart.yaml"

    if values_json == None and values == None:
        values = "values.yaml"

    if templates == None:
        # https://github.com/helm/helm/blob/a73c51ca08297fda17f40b3b11ff602e22893334/pkg/lint/rules/template.go#L208
        templates = native.glob(
            [
                "templates/**/*.yaml",
                "templates/**/*.yml",
                "templates/**/*.tpl",
                "templates/**/*.txt",
            ],
            allow_empty = True,
        )

    if crds == None:
        crds = native.glob(["crds/**/*.yaml"], allow_empty = True)

    # values.schema.json is an optional file, use glob to check if it exists:
    if schema == None and len(native.glob(["values.schema.json"], allow_empty = True)):
        schema = "values.schema.json"

    helm_package(
        name = name,
        chart = chart,
        chart_json = chart_json,
        crds = crds,
        deps = deps,
        files = files,
        images = images,
        stamp = stamp,
        substitutions = substitutions,
        templates = templates,
        values = values,
        values_json = values_json,
        schema = schema,
        **kwargs
    )

    helm_push_images(
        name = name + ".push_images",
        package = name,
        **kwargs
    )

    if registry_url:
        helm_push(
            name = name + ".push_registry",
            package = name,
            include_images = False,
            registry_url = registry_url,
            login_url = login_url,
            push_cmd = push_cmd,
            **kwargs
        )

        helm_push(
            name = name + ".push",
            include_images = True,
            package = name,
            registry_url = registry_url,
            login_url = login_url,
            push_cmd = push_cmd,
            **kwargs
        )

    if not install_name:
        install_name = name.replace("_", "-")

    helm_install(
        name = name + ".install",
        install_name = install_name,
        package = name,
        helm_opts = helm_opts,
        opts = install_opts,
        data = data,
        **kwargs
    )

    helm_upgrade(
        name = name + ".upgrade",
        install_name = install_name,
        package = name,
        helm_opts = helm_opts,
        opts = upgrade_opts,
        data = data,
        **kwargs
    )

    helm_uninstall(
        name = name + ".uninstall",
        install_name = install_name,
        helm_opts = helm_opts,
        opts = uninstall_opts,
        data = data,
        **kwargs
    )

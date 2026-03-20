"""Rules for generating Helm charts."""

load("//helm/private:json_to_yaml.bzl", "json_to_yaml")

def chart_content(
        name,
        api_version = "v2",
        description = "A Helm chart for Kubernetes by Bazel.",
        type = "application",
        version = "0.1.0",
        app_version = "1.16.0",
        icon = None):
    """A convenience wrapper for defining Chart.yaml files with [helm_package.chart_json](#helm_package-chart_json).

    Args:
        name (str): The name of the chart
        api_version (str, optional): The Helm API version
        description (str, optional): A descritpion of the chart.
        type (str, optional): The chart type.
        version (str, optional): The chart version.
        app_version (str, optional): The version number of the application being deployed.
        icon (str, optional): A URL to an SVG or PNG image to be used as an icon.

    Returns:
        str: A json encoded string which represents `Chart.yaml` contents.
    """
    content = {
        "apiVersion": api_version,
        "appVersion": app_version,
        "description": description,
        "name": name,
        "type": type,
        "version": version,
    }
    if icon:
        content["icon"] = icon
    return json.encode(content)

def _chart_file_impl(ctx):
    """A rule for generating a `Chart.yaml` file."""

    name = ctx.attr.chart_name or ctx.label.name

    content = chart_content(
        name = name,
        api_version = ctx.attr.api_version,
        description = ctx.attr.description,
        type = ctx.attr.type,
        version = ctx.attr.version,
        app_version = ctx.attr.app_version,
        icon = ctx.attr.icon or None,
    )

    content_yaml = json_to_yaml(
        ctx = ctx,
        name = ctx.label.name,
        json_content = content,
    )

    return [DefaultInfo(
        files = depset([content_yaml]),
    )]

chart_file = rule(
    implementation = _chart_file_impl,
    doc = "Create a Helm chart file.",
    attrs = {
        "api_version": attr.string(
            default = "v2",
            doc = "The Helm API version",
        ),
        "app_version": attr.string(
            default = "1.16.0",
            doc = "The version number of the application being deployed.",
        ),
        "chart_name": attr.string(
            doc = "The name of the chart",
        ),
        "description": attr.string(
            default = "A Helm chart for Kubernetes by Bazel.",
            doc = "A descritpion of the chart.",
        ),
        "icon": attr.string(
            doc = "A URL to an SVG or PNG image to be used as an icon.",
        ),
        "type": attr.string(
            default = "application",
            doc = "The chart type.",
        ),
        "version": attr.string(
            default = "0.1.0",
            doc = "The chart version.",
        ),
        "_json_to_yaml": attr.label(
            doc = "A tools for converting json files to yaml files.",
            cfg = "exec",
            executable = True,
            default = Label("//helm/private/json_to_yaml"),
        ),
    },
)

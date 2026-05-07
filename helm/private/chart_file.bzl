"""Rules for generating Helm charts."""

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
    output = ctx.actions.declare_file("Chart.yaml")

    args = ctx.actions.args()
    args.add("-name", name)
    args.add("-api-version", ctx.attr.api_version)
    args.add("-description", ctx.attr.description)
    args.add("-type", ctx.attr.type)
    args.add("-output", output)

    inputs = []

    if ctx.file.version_file:
        args.add("-version-file", ctx.file.version_file)
        inputs.append(ctx.file.version_file)
    else:
        args.add("-version", ctx.attr.version)

    if ctx.file.app_version_file:
        args.add("-app-version-file", ctx.file.app_version_file)
        inputs.append(ctx.file.app_version_file)
    else:
        args.add("-app-version", ctx.attr.app_version)

    if ctx.attr.icon:
        args.add("-icon", ctx.attr.icon)

    ctx.actions.run(
        executable = ctx.executable._tool,
        arguments = [args],
        inputs = inputs,
        outputs = [output],
        mnemonic = "HelmChartFile",
        progress_message = "Generating Chart.yaml for %s" % name,
    )

    return [DefaultInfo(
        files = depset([output]),
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
        "app_version_file": attr.label(
            allow_single_file = True,
            doc = "A file containing the version number of the application being deployed.",
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
        "version_file": attr.label(
            allow_single_file = True,
            doc = "A file containing the chart version.",
        ),
        "_tool": attr.label(
            doc = "The chart_file tool.",
            cfg = "exec",
            executable = True,
            default = Label("//helm/private/chart_file"),
        ),
    },
)

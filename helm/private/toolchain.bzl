"""rules_helm toolchain implementation"""

HelmPluginInfo = provider(
    doc = "Info about a Helm plugin.",
    fields = {
        "data": "Depset[File]: Files associated with the plugin.",
        "name": "String: The name of the plugin.",
        "yaml": "File: The yaml file representing the plugin.",
    },
)

def _helm_plugin_impl(ctx):
    name = ctx.attr.plugin_name
    if not name:
        name = ctx.label.name

    return [
        HelmPluginInfo(
            yaml = ctx.file.yaml,
            name = name,
            data = depset(ctx.files.data),
        ),
    ]

helm_plugin = rule(
    doc = "Define a [helm plugin](https://helm.sh/docs/topics/plugins/).",
    implementation = _helm_plugin_impl,
    attrs = {
        "data": attr.label_list(
            doc = "Additional files associated with the plugin.",
            allow_files = True,
        ),
        "plugin_name": attr.string(
            doc = "An explicit name for the plugin. If unset, `name` will be used.",
        ),
        "yaml": attr.label(
            doc = "The yaml file representing the plugin",
            allow_single_file = True,
            mandatory = True,
        ),
    },
)

def _create_plugins_dir(*, ctx, plugins, output):
    manifest = ctx.actions.declare_file("{}.manifest".format(output.basename), sibling = output)
    manifest_data = {}
    inputs = [depset([manifest])]
    for plugin in plugins:
        info = plugin[HelmPluginInfo]
        inputs.append(depset([info.yaml], transitive = [info.data]))

        if info.name in manifest_data:
            fail("Two plugins sharing the name {} were provided. Please update {}".format(
                info.name,
                ctx.label,
            ))

        manifest_data[info.name] = {
            "data": [f.path for f in info.data.to_list()],
            "yaml": info.yaml.path,
        }

    ctx.actions.write(
        output = manifest,
        content = json.encode_indent(manifest_data, indent = " " * 4) + "\n",
    )

    args = ctx.actions.args()
    args.add("-manifest", manifest)
    args.add("-output", output.path)

    ctx.actions.run(
        mnemonic = "HelmPluginsDir",
        progress_message = "HelmPluginsDir %{label}",
        executable = ctx.executable._plugins_builder,
        arguments = [args],
        inputs = depset(transitive = inputs),
        outputs = [output],
    )

    return output

def _helm_toolchain_impl(ctx):
    binary = ctx.file.helm

    plugins_dir = _create_plugins_dir(
        ctx = ctx,
        plugins = ctx.attr.plugins,
        output = ctx.actions.declare_directory("{}.plugins".format(ctx.label.name)),
    )

    template_variables = platform_common.TemplateVariableInfo({
        "HELM_BIN": binary.path,
        "HELM_PLUGINS": plugins_dir.path,
    })

    default_info = DefaultInfo(
        files = depset([binary]),
        runfiles = ctx.runfiles(files = [binary, plugins_dir]),
    )

    toolchain_info = platform_common.ToolchainInfo(
        default_info = default_info,
        helm = binary,
        helm_plugins = plugins_dir,
        template_variables = template_variables,
    )

    return [default_info, toolchain_info, template_variables]

helm_toolchain = rule(
    implementation = _helm_toolchain_impl,
    doc = "A helm toolchain.",
    attrs = {
        "helm": attr.label(
            doc = "A helm binary",
            allow_single_file = True,
            mandatory = True,
            cfg = "exec",
        ),
        "plugins": attr.label_list(
            doc = "Additional plugins to make available to helm.",
            cfg = "exec",
            providers = [HelmPluginInfo],
        ),
        "_plugins_builder": attr.label(
            default = Label("//helm/private/plugin:plugin_builder"),
            cfg = "exec",
            executable = True,
        ),
    },
)

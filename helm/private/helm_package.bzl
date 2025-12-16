"""Helm rules"""

load("//helm/private:helm_utils.bzl", "is_stamping_enabled")
load("//helm/private:json_to_yaml.bzl", "json_to_yaml")
load(":image_utils.bzl", "ImagePushRepositoryInfo", "image_push_repository_aspect")
load(":providers.bzl", "HelmPackageInfo")

def _rlocationpath(file, workspace_name):
    if file.short_path.startswith("../"):
        return file.short_path[len("../"):]

    return "{}/{}".format(workspace_name, file.short_path)

def _helm_package_impl(ctx):
    if (ctx.attr.chart and ctx.attr.chart_json) or (not ctx.attr.chart and not ctx.attr.chart_json):
        fail("Helm package {} must have either a `chart` or `chart_json` attribute".format(
            ctx.label,
        ))

    if (ctx.attr.values and ctx.attr.values_json) or (not ctx.attr.values and not ctx.attr.values_json):
        fail("Helm package {} must have either a `values` or `values_json` attribute".format(
            ctx.label,
        ))

    if ctx.attr.chart_json:
        chart_yaml = json_to_yaml(
            ctx = ctx,
            name = "{}/Chart.yaml".format(ctx.label.name),
            json_content = ctx.attr.chart_json,
        )
    else:
        chart_yaml = ctx.file.chart

    if ctx.attr.values_json:
        values_yaml = json_to_yaml(
            ctx = ctx,
            name = "{}/values.yaml".format(ctx.label.name),
            json_content = ctx.attr.values_json,
        )
    else:
        values_yaml = ctx.file.values

    args = ctx.actions.args()

    output = ctx.actions.declare_file(ctx.label.name + ".tgz")
    metadata_output = ctx.actions.declare_file(ctx.label.name + ".metadata.json")
    args.add("-output", output)
    args.add("-metadata_output", metadata_output)

    toolchain = ctx.toolchains[Label("//helm:toolchain_type")]
    args.add("-helm", toolchain.helm)
    args.add("-helm_plugins", toolchain.helm_plugins.path)

    args.add("-chart", chart_yaml)
    args.add("-values", values_yaml)

    if ctx.file.schema:
        args.add("-schema", ctx.file.schema)

    args.add("-package", "{}/{}".format(
        ctx.label.workspace_name if ctx.label.workspace_name else ctx.workspace_name,
        ctx.label.package,
    ))

    substitutions_file = ctx.actions.declare_file("{}/substitutions.json".format(ctx.label.name))
    ctx.actions.write(
        output = substitutions_file,
        content = json.encode_indent(ctx.attr.substitutions, indent = " " * 4),
    )
    args.add("-substitutions", substitutions_file)

    templates_manifest = ctx.actions.declare_file("{}/templates_manifest.json".format(ctx.label.name))
    ctx.actions.write(
        output = templates_manifest,
        content = json.encode_indent({file.path: _rlocationpath(file, ctx.workspace_name) for file in ctx.files.templates}, indent = " " * 4),
    )
    args.add("-templates_manifest", templates_manifest)

    files_manifest = ctx.actions.declare_file("{}/files_manifest.json".format(ctx.label.name))
    ctx.actions.write(
        output = files_manifest,
        content = json.encode_indent({file.path: _rlocationpath(file, ctx.workspace_name) for file in ctx.files.files}, indent = " " * 4),
    )
    args.add("-files_manifest", files_manifest)

    crds_manifest = ctx.actions.declare_file("{}/crds_manifest.json".format(ctx.label.name))
    ctx.actions.write(
        output = crds_manifest,
        content = json.encode_indent({file.path: _rlocationpath(file, ctx.workspace_name) for file in ctx.files.crds}, indent = " " * 4),
    )
    args.add("-crds_manifest", crds_manifest)

    deps = []
    if ctx.attr.deps:
        deps.extend([dep[HelmPackageInfo].chart for dep in ctx.attr.deps])
        deps_manifest = ctx.actions.declare_file("{}/deps_manifest.json".format(ctx.label.name))
        ctx.actions.write(
            output = deps_manifest,
            content = json.encode_indent([dep.path for dep in deps], indent = " " * 4),
        )
        args.add("-deps_manifest", deps_manifest)
        deps.append(deps_manifest)

    # Create documents for each image the package depends on
    image_inputs = []
    single_image_manifests = []
    for image in ctx.attr.images:
        image_inputs.append(image[ImagePushRepositoryInfo].repository_file)

        # Add the appropriate image file based on format
        if image[ImagePushRepositoryInfo].oci_layout:
            image_inputs.append(image[ImagePushRepositoryInfo].oci_layout)
        elif image[ImagePushRepositoryInfo].manifest_file:
            image_inputs.append(image[ImagePushRepositoryInfo].manifest_file)
        single_image_manifest = ctx.actions.declare_file("{}/{}".format(
            ctx.label.name,
            str(image.label).strip("@").replace("/", "_").replace(":", "_") + ".image_manifest",
        ))
        push_info = image[DefaultInfo]

        remote_tags_path = None
        if image[ImagePushRepositoryInfo].remote_tags_file:
            remote_tags_path = image[ImagePushRepositoryInfo].remote_tags_file.path
            image_inputs.append(image[ImagePushRepositoryInfo].remote_tags_file)

        # Set mutually exclusive fields based on image format
        oci_layout_dir = None
        manifest_file = None
        if image[ImagePushRepositoryInfo].oci_layout:
            oci_layout_dir = image[ImagePushRepositoryInfo].oci_layout.path
        elif image[ImagePushRepositoryInfo].manifest_file:
            manifest_file = image[ImagePushRepositoryInfo].manifest_file.path
        else:
            fail("Unable to determine repository info for {}".format(image.label))

        ctx.actions.write(
            output = single_image_manifest,
            content = json.encode_indent(
                struct(
                    label = str(image.label),
                    repository_path = image[ImagePushRepositoryInfo].repository_file.path,
                    oci_layout_dir = oci_layout_dir,
                    manifest_file = manifest_file,
                    remote_tags_path = remote_tags_path,
                ),
            ),
        )
        image_inputs.extend(push_info.default_runfiles.files.to_list())
        single_image_manifests.append(single_image_manifest)

    image_manifest = ctx.actions.declare_file("{}/image_manifest.json".format(ctx.label.name))
    ctx.actions.write(
        output = image_manifest,
        content = json.encode_indent([manifest.path for manifest in single_image_manifests], indent = " " * 4),
    )
    image_inputs.append(image_manifest)
    image_inputs.extend(single_image_manifests)
    args.add("-image_manifest", image_manifest)
    stamps = []
    if is_stamping_enabled(ctx.attr):
        args.add("-volatile_status_file", ctx.version_file)
        args.add("-stable_status_file", ctx.info_file)
        stamps.extend([ctx.version_file, ctx.info_file])

    args.add("-workspace_name", ctx.workspace_name)

    ctx.actions.run(
        executable = ctx.executable._packager,
        outputs = [output, metadata_output],
        inputs = depset(
            ctx.files.templates + ctx.files.schema + ctx.files.files + ctx.files.crds + stamps + image_inputs + deps + [
                chart_yaml,
                values_yaml,
                templates_manifest,
                files_manifest,
                crds_manifest,
                substitutions_file,
            ],
        ),
        tools = depset([toolchain.helm]),
        mnemonic = "HelmPackage",
        arguments = [args],
        progress_message = "Creating Helm Package for {}".format(
            ctx.label,
        ),
    )

    return [
        DefaultInfo(
            files = depset([output]),
            runfiles = ctx.runfiles([output]),
        ),
        HelmPackageInfo(
            chart = output,
            metadata = metadata_output,
            images = ctx.attr.images,
        ),
    ]

helm_package = rule(
    implementation = _helm_package_impl,
    doc = "Rules for creating Helm chart packages.",
    attrs = {
        "chart": attr.label(
            doc = "The `Chart.yaml` file of the helm chart",
            allow_single_file = True,
        ),
        "chart_json": attr.string(
            doc = "The `Chart.yaml` file of the helm chart as a json object",
        ),
        "crds": attr.label_list(
            doc = (
                "All [Custom Resource Definitions](https://helm.sh/docs/chart_best_practices/custom_resource_definitions/) " +
                "associated with the current helm chart. E.g., the `./crds` directory"
            ),
            default = [],
            allow_files = [".yaml"],
        ),
        "deps": attr.label_list(
            doc = "Other helm packages this package depends on.",
            providers = [HelmPackageInfo],
        ),
        "files": attr.label_list(
            doc = "Files accessed in templates via the [`.Files` api](https://helm.sh/docs/chart_template_guide/accessing_files/)",
            allow_files = True,
            default = [],
        ),
        "images": attr.label_list(
            doc = """\
                A list of \
                [oci_push](https://github.com/bazel-contrib/rules_oci/blob/main/docs/push.md#oci_push_rule-remote_tags) or \
                [image_push](https://github.com/bazel-contrib/rules_img) \
                targets.""",
            aspects = [image_push_repository_aspect],
        ),
        "schema": attr.label(
            doc = "The `values.schema.json` file for the current package.",
            allow_single_file = True,
        ),
        "stamp": attr.int(
            doc = """\
                Whether to encode build information into the helm actions. Possible values:

                - `stamp = 1`: Always stamp the build information into the helm actions, even in \
                [--nostamp](https://docs.bazel.build/versions/main/user-manual.html#flag--stamp) builds. \
                This setting should be avoided, since it potentially kills remote caching for the target and \
                any downstream actions that depend on it.

                - `stamp = 0`: Always replace build information by constant values. This gives good build result caching.

                - `stamp = -1`: Embedding of build information is controlled by the \
                [--[no]stamp](https://docs.bazel.build/versions/main/user-manual.html#flag--stamp) flag.

                Stamped targets are not rebuilt unless their dependencies change.
            """,
            default = -1,
            values = [1, 0, -1],
        ),
        "substitutions": attr.string_dict(
            doc = "A dictionary of substitutions to apply to the `values.yaml` file.",
            default = {},
        ),
        "templates": attr.label_list(
            doc = "All templates associated with the current helm chart. E.g., the `./templates` directory",
            allow_files = [".yaml", ".yml", ".tpl", ".txt"],
        ),
        "values": attr.label(
            doc = "The `values.yaml` file for the current package.",
            allow_single_file = True,
        ),
        "values_json": attr.string(
            doc = "The `values.yaml` file for the current package as a json object.",
        ),
        "_json_to_yaml": attr.label(
            doc = "A tools for converting json files to yaml files.",
            cfg = "exec",
            executable = True,
            default = Label("//helm/private/json_to_yaml"),
        ),
        "_packager": attr.label(
            doc = "A process wrapper for producing the helm package's `tgz` file",
            cfg = "exec",
            executable = True,
            default = Label("//helm/private/packager"),
        ),
        "_stamp_flag": attr.label(
            doc = "A setting used to determine whether or not the `--stamp` flag is enabled",
            default = Label("//helm/private:stamp"),
        ),
    },
    toolchains = [
        str(Label("@rules_helm//helm:toolchain_type")),
    ],
)

"""kubectl toolchain implementation"""

def _kubectl_toolchain_impl(ctx):
    binary = ctx.file.kubectl

    template_variables = platform_common.TemplateVariableInfo({
        "KUBECTL_BIN": binary.path,
    })

    default_info = DefaultInfo(
        files = depset([binary]),
        runfiles = ctx.runfiles(files = [binary]),
    )

    toolchain_info = platform_common.ToolchainInfo(
        default_info = default_info,
        kubectl = binary,
        template_variables = template_variables,
    )

    return [default_info, toolchain_info, template_variables]

kubectl_toolchain = rule(
    implementation = _kubectl_toolchain_impl,
    doc = """\
A kubectl toolchain.

Exposes the binary as `KUBECTL_BIN` to rules that consume
`@rules_helm//k8s:current_kubectl_toolchain` via `toolchains`, e.g.

```python
genrule(
    name = "pods",
    outs = ["pods.txt"],
    cmd = "$(KUBECTL_BIN) version --client > $@",
    toolchains = ["@rules_helm//k8s:current_kubectl_toolchain"],
)
```
""",
    attrs = {
        "kubectl": attr.label(
            doc = "A kubectl binary",
            allow_single_file = True,
            mandatory = True,
            cfg = "exec",
        ),
    },
)

# rules_helm

Bazel rules for producing [helm charts][helm]

[helm]: https://helm.sh/

## Setup MODULE.bazel

`rules_helm` is published to the
[Bazel Central Registry](https://registry.bazel.build/modules/rules_helm):

```python
bazel_dep(name = "rules_helm", version = "{version}")
```

## Run as a tool

```bash
bazel run @helm//:helm -- ...
```

A matching `kubectl` is available for inspecting the cluster after a deploy. See
[Kubernetes tools](./k8s.md) for setup.

```bash
bazel run @kubectl//:kubectl -- ...
```

## Use in a genrule

```python
genrule(
    name = "genrule",
    srcs = [":chart"],
    outs = ["template.yaml"],
    cmd = "$(HELM_BIN) template my-chart $(execpath :chart) > $@",
    toolchains = ["@rules_helm//helm:current_toolchain"],
)
```

## Environment variables

### `RULES_HELM_IMAGE_PUSH_CONCURRENCY`

How many of a chart's bundled image pushers run at once. Defaults to `4`, and applies to
[helm_push](https://periareon.github.io/rules_helm/defs.html#helm_push),
[helm_push_images](https://periareon.github.io/rules_helm/defs.html#helm_push_images),
[helm_install](https://periareon.github.io/rules_helm/defs.html#helm_install) and
[helm_upgrade](https://periareon.github.io/rules_helm/defs.html#helm_upgrade).

Each image is pushed by its own process, which authenticates with the registry before it looks at
anything, so a chart with many images spends most of the push waiting rather than transferring.
Running the pushers concurrently keeps that cost from scaling with the image count.

Set it to `1` to push one image at a time. A serial run also streams each pusher's output live on
its own streams, instead of capturing it and replaying it as a block once the pusher exits, which
makes a single failing push easier to follow.

Values that are not a positive integer are ignored with a warning.

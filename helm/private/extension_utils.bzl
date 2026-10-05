"""Helpers shared by the rules_helm module extensions."""

def find_modules(module_ctx):
    """Locate the root module and the `rules_helm` module.

    Args:
        module_ctx (module_ctx): The module extension context.

    Returns:
        tuple: `(root_module, rules_helm_module)`. When evaluated outside of a
            root module (e.g. in a `bazel mod` query) the root falls back to the
            `rules_helm` module itself.
    """
    root = None
    rules_module = None
    for mod in module_ctx.modules:
        if mod.is_root:
            root = mod
        if mod.name == "rules_helm":
            rules_module = mod
    if root == None:
        root = rules_module
    if rules_module == None:
        fail("Unable to find rules_helm module")

    return root, rules_module

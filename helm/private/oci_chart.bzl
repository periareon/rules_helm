"""Helpers for locating a Helm chart in an OCI registry.

These work with both `repository_ctx` and `module_ctx`.
"""

# https://helm.sh/docs/topics/registries/#helm-chart-manifest
_CONFIG_MEDIA_TYPE = "application/vnd.cncf.helm.config.v1+json"
_CHART_LAYER_MEDIA_TYPE = "application/vnd.cncf.helm.chart.content.v1.tar+gzip"

def _parse_url(chart_url):
    """Split an `oci://<host>/<path>:<version>` chart url.

    Args:
        chart_url (str): The chart url.

    Returns:
        struct: The `hostname`, `path`, `version` and `name` of the chart, where
            `name` is the last segment of `path`. `None` if the url does not have
            the form `oci://<host>/<path>:<version>`.
    """
    for char in chart_url.elems():
        if char.isspace():
            return None

    url, _, version = chart_url.rpartition(":")
    hostname, _, path = url.removeprefix("oci://").partition("/")
    if not (
        chart_url.startswith("oci://") and
        hostname and
        path and
        "" not in path.split("/") and
        version and
        "/" not in version and
        ":" not in path and
        "@" not in path
    ):
        return None

    return struct(
        hostname = hostname,
        path = path,
        version = version,
        name = path.rpartition("/")[2],
    )

def _parse_url_or_fail(chart_url):
    """Like `parse_url`, but fail with a message that names the url if it is malformed.

    Args:
        chart_url (str): The chart url.

    Returns:
        struct: The chart, as for `parse_url`.
    """
    chart = _parse_url(chart_url)
    if not chart:
        fail("`{}` is not a chart url of the form `oci://<host>/<path>:<version>`".format(chart_url))
    return chart

def _blob_url(chart, digest):
    """Return the url of a blob in the chart's repository.

    Args:
        chart (struct): A chart from `parse_url`.
        digest (str): The blob digest, in the form `sha256:<hex>`.

    Returns:
        str: The blob url.
    """
    return "https://{}/v2/{}/blobs/{}".format(chart.hostname, chart.path, digest)

def _find_chart_layer(ctx, au, chart_url):
    """Find the layer that holds the chart package in the image manifest.

    Args:
        ctx (ctx): The `repository_ctx` or `module_ctx` used to download the manifest.
        au (struct): An authenticator from `authn.new`.
        chart_url (str): The chart url.

    Returns:
        struct: The `digest` of the layer, in the form `sha256:<hex>`, and the
            `token` that authenticates requests to the registry.
    """
    chart = _parse_url_or_fail(chart_url)
    token = au.get_token(chart.hostname, chart.path)

    manifest_json = "manifest.json"
    manifest_url = "https://{}/v2/{}/manifests/{}".format(
        chart.hostname,
        chart.path,
        chart.version,
    )
    ctx.download(
        output = manifest_json,
        url = manifest_url,
        auth = {
            manifest_url: token,
        },
        # Copied from `helm pull --debug`
        headers = {
            "Accept": [
                "application/vnd.docker.distribution.manifest.v2+json",
                "application/vnd.docker.distribution.manifest.list.v2+json",
                "application/vnd.oci.image.manifest.v1+json",
                "application/vnd.oci.image.index.v1+json",
                "*/*",
            ],
        },
    )
    manifest = json.decode(ctx.read(manifest_json))

    if manifest.get("config", {}).get("mediaType") != _CONFIG_MEDIA_TYPE:
        fail("{} is not a Helm chart package".format(chart_url))

    for layer in manifest["layers"]:
        if layer["mediaType"] == _CHART_LAYER_MEDIA_TYPE:
            return struct(digest = layer["digest"], token = token)
    fail("could not find chart content layer")

def _resolve_sha256(ctx, au, chart_url):
    """Look up the sha256 of a chart package in the registry.

    Args:
        ctx (ctx): The `repository_ctx` or `module_ctx` used to download the manifest.
        au (struct): An authenticator from `authn.new`.
        chart_url (str): The chart url.

    Returns:
        str: The hex-encoded sha256 of the chart package.
    """
    digest = _find_chart_layer(ctx, au, chart_url).digest
    algorithm, _, sha256 = digest.partition(":")
    if algorithm != "sha256":
        fail("{} has a chart layer with the unsupported digest {}".format(chart_url, digest))
    return sha256

oci_chart = struct(
    blob_url = _blob_url,
    find_chart_layer = _find_chart_layer,
    parse_url = _parse_url,
    parse_url_or_fail = _parse_url_or_fail,
    resolve_sha256 = _resolve_sha256,
)

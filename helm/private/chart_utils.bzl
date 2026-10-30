"""Helpers for importing Helm charts that need no repository or module context."""

def _is_sha256(value):
    """Check that a value is a hex-encoded sha256 digest in lower case.

    Args:
        value (object): The value to check.

    Returns:
        bool: True if the value is a string of 64 lower case hex digits.
    """
    return type(value) == "string" and len(value) == 64 and not value.strip("0123456789abcdef")

def _is_chart_url(url):
    """Check that a url has the form `oci://<host>/<path>:<version>`.

    Args:
        url (str): The url to check.

    Returns:
        bool: True if the url has that form.
    """
    for char in url.elems():
        if char.isspace():
            return False

    url_without_version, _, version = url.rpartition(":")
    hostname, _, path = url_without_version.removeprefix("oci://").partition("/")
    return bool(
        url.startswith("oci://") and
        hostname and
        path and
        "" not in path.split("/") and
        version and
        "/" not in version and
        ":" not in path and
        "@" not in path,
    )

def _starts_with_version(text):
    """Check that text starts like a version: an optional `v`, then `<digits>.<digit>`."""
    major, dot, rest = text.removeprefix("v").partition(".")
    return bool(dot and major.isdigit() and rest[:1].isdigit())

def _split_chart_file(chart_file):
    """Split a chart file name into the chart name and the version.

    A chart file is named `<name>-<version>.tgz`. Both parts can contain a dash,
    so the version starts at the first dash that is followed by a version number.

    Args:
        chart_file (str): The chart file name.

    Returns:
        tuple: The chart name and the chart version.
    """
    stem = chart_file.removesuffix(".tgz")
    parts = stem.split("-")
    for i in range(1, len(parts)):
        if _starts_with_version(parts[i]):
            return "-".join(parts[:i]), "-".join(parts[i:])

    # No version number: split at the last dash.
    name, _, version = stem.rpartition("-")
    return name, version

def _chart_sha256(pinned, url, facts, lookup):
    """Choose the sha256 for a chart from a tag, the stored facts or the registry.

    Args:
        pinned (str): The sha256 set in the tag, or an empty string.
        url (str): The chart url.
        facts (dict or Facts): The digests stored by a previous evaluation, by chart url. Only `get` is called on it.
        lookup (callable): Called with the chart url, returns the sha256 from the registry.

    Returns:
        struct: The `sha256` to use, and `is_fact`, which is True when the digest
            did not come from the tag and so belongs in the stored facts.
    """
    if pinned:
        return struct(sha256 = pinned, is_fact = False)

    sha256 = facts.get(url)
    if not _is_sha256(sha256):
        sha256 = lookup(url)
    return struct(sha256 = sha256, is_fact = True)

chart_utils = struct(
    chart_sha256 = _chart_sha256,
    is_chart_url = _is_chart_url,
    is_sha256 = _is_sha256,
    split_chart_file = _split_chart_file,
)

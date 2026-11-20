"""Helpers for importing Helm charts that need no repository or module context."""

def _is_sha256(value):
    """Check that a value is a hex-encoded sha256 digest in lower case.

    Args:
        value (object): The value to check.

    Returns:
        bool: True if the value is a string of 64 lower case hex digits.
    """
    return type(value) == "string" and len(value) == 64 and not value.strip("0123456789abcdef")

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

def _quoted(value):
    """Read a quoted YAML scalar up to its closing quote.

    Args:
        value (str): A string that starts with `'` or `"`.

    Returns:
        str: The text between the quotes, or `None` if the quote is not closed.
    """
    quote = value[0]
    escaped = False
    for i in range(1, len(value)):
        char = value[i]
        if escaped:
            escaped = False
        elif char == "\\" and quote == '"':
            escaped = True
        elif char == quote:
            return value[1:i]
    return None

def _scalar(value):
    """Read the value of a one-line YAML scalar, without quotes or a trailing comment.

    Args:
        value (str): The text after the `:` of a `key: value` line.

    Returns:
        str: The value. A block scalar indicator such as `>-` is returned as it is.
    """
    value = value.strip()
    if value[:1] in ["'", '"']:
        text = _quoted(value)
        if text != None:
            return text
        return value

    # A comment starts at a `#` that follows whitespace.
    comment = value.replace("\t", " ").find(" #")
    if comment >= 0:
        value = value[:comment].rstrip()
    return value

def _parse_chart_yaml(content):
    """Read the top-level scalars and the `annotations` of a `Chart.yaml`.

    `Chart.yaml` is a flat mapping of scalars, lists and the `annotations`
    mapping of strings, which is all this handles. Block scalars (`>`, `|`) are
    not read: the field gets the indicator as its value.

    Args:
        content (str): The content of `Chart.yaml`.

    Returns:
        tuple: The top-level scalar fields and the annotations, both `dict[str, str]`.
    """
    fields = {}
    annotations = {}
    section = None
    for line in content.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if not line[0].isspace() and not stripped.startswith("-"):
            key, sep, value = stripped.partition(":")
            if not sep:
                continue
            section = key.strip()
            value = _scalar(value)
            if value:
                fields[section] = value
        elif section == "annotations" and not stripped.startswith("-"):
            key, sep, value = stripped.partition(":")
            if sep:
                annotations[key.strip()] = _scalar(value)
    return fields, annotations

_NAME_CHARACTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._"

def _is_chart_name(value):
    """Check that a chart name is safe to use as a target name.

    Args:
        value (str): The `name` of a `Chart.yaml`.

    Returns:
        bool: True if the value is not empty and has only letters, digits, `-`, `.` and `_`.
    """
    return type(value) == "string" and bool(value) and not value.strip(_NAME_CHARACTERS)

def _is_chart_version(value):
    """Check that a chart version is safe to write into a `BUILD.bazel` file.

    Args:
        value (str): The `version` of a `Chart.yaml`.

    Returns:
        bool: True if the value is not empty and has only letters, digits, `-`, `.`, `_` and `+`.
    """
    return type(value) == "string" and bool(value) and not value.strip(_NAME_CHARACTERS + "+")

chart_utils = struct(
    chart_sha256 = _chart_sha256,
    is_chart_name = _is_chart_name,
    is_chart_version = _is_chart_version,
    is_sha256 = _is_sha256,
    parse_chart_yaml = _parse_chart_yaml,
    scalar = _scalar,
)

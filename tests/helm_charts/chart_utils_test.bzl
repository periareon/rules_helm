"""Unit tests for the chart import helpers."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

# buildifier: disable=bzl-visibility
load("//helm/private:chart_utils.bzl", "chart_utils")

# buildifier: disable=bzl-visibility
load("//helm/private:oci_chart.bzl", "oci_chart")

_SHA = "d0c202f57b8653eb957fb5b2f9472c1b11cf6b51acc5c777e4b824f7b5a9ea87"
_OTHER_SHA = "9abd372c9d843b974d918442cd0e68c9669f57d8630566ce74dfaf63447c282a"
_URL = "oci://quay.io/jetstack/charts/cert-manager:1.19.4"

def _is_sha256_test_impl(ctx):
    env = unittest.begin(ctx)
    asserts.true(env, chart_utils.is_sha256(_SHA))
    for value in [
        None,
        "",
        "abc",
        _SHA.upper(),
        "sha256:" + _SHA,
        _SHA + "0",
        _SHA[:-1] + "g",
    ]:
        asserts.false(env, chart_utils.is_sha256(value), str(value))
    return unittest.end(env)

is_sha256_test = unittest.make(_is_sha256_test_impl)

def _parse_url_test_impl(ctx):
    env = unittest.begin(ctx)
    for url, (hostname, path, version, name) in [
        (_URL, ("quay.io", "jetstack/charts/cert-manager", "1.19.4", "cert-manager")),
        ("oci://public.ecr.aws/karpenter/karpenter:1.9.0", ("public.ecr.aws", "karpenter/karpenter", "1.9.0", "karpenter")),
        ("oci://localhost:5000/charts/app:1.0.0-rc.1", ("localhost:5000", "charts/app", "1.0.0-rc.1", "app")),
        ("oci://quay.io/jetstack/charts/cert-manager:1.21.0-beta.0", ("quay.io", "jetstack/charts/cert-manager", "1.21.0-beta.0", "cert-manager")),
        ("oci://example.com/foo-1.2-bar:3.0.0", ("example.com", "foo-1.2-bar", "3.0.0", "foo-1.2-bar")),
    ]:
        chart = oci_chart.parse_url(url)
        asserts.equals(env, (hostname, path, version, name), (chart.hostname, chart.path, chart.version, chart.name), url)
    for url in [
        "",
        "oci://quay.io/jetstack/charts/cert-manager",
        "oci://quay.io:443/cert-manager",
        "oci://quay.io/jetstack/charts/cert-manager:",
        "oci://quay.io/jetstack/charts/cert-manager@sha256:abc",
        "oci://quay.io/a:1:2",
        "oci:///x/y:1",
        "oci://quay.io//jetstack/charts/cert-manager:1.19.4",
        "oci://quay.io/jetstack/charts/cert-manager/:1.19.4",
        "oci://quay.io/jetstack/charts/cert-manager:1.19.4\n",
        "oci://quay.io/jetstack/charts/cert-manager:1.19.4 ",
        "oci://quay.io/jetstack/charts/cert manager:1.19.4",
        "oci://quay.io/jetstack/charts/cert-manager:1.19.4\t",
        "oci://quay.io:1",
        "https://quay.io/jetstack/charts/cert-manager:1.19.4",
    ]:
        asserts.equals(env, None, oci_chart.parse_url(url), url)
    return unittest.end(env)

parse_url_test = unittest.make(_parse_url_test_impl)

def _parse_chart_yaml_test_impl(ctx):
    env = unittest.begin(ctx)

    fields, annotations = chart_utils.parse_chart_yaml("""\
# A comment line.
apiVersion: v2
name: cert-manager
version: v1.19.4
description: "A chart: with a colon # and a hash"
keywords:
  - certificates
dependencies:
  - name: other
    version: 9.9.9
annotations:
  licenses: Apache-2.0
  artifacthub.io/license: 'MIT'
""")
    asserts.equals(env, {
        "apiVersion": "v2",
        "description": "A chart: with a colon # and a hash",
        "name": "cert-manager",
        "version": "v1.19.4",
    }, fields)

    # buildifier: disable=attr-licenses
    asserts.equals(env, {"artifacthub.io/license": "MIT", "licenses": "Apache-2.0"}, annotations)

    # A comment after a value is not part of the value.
    for line, value in [
        ("foo # chart", "foo"),
        ("foo\t# chart", "foo"),
        ('"foo" # chart', "foo"),
        ("'foo' # it's a chart", "foo"),
        ("1.2.3 # x-release-please-version", "1.2.3"),
        ('"1.2.3"   #', "1.2.3"),
        ("foo#bar", "foo#bar"),
        ('"foo # bar"', "foo # bar"),
        ('"a\\"b" # c', 'a\\"b'),
        ("  foo  ", "foo"),
        # A block scalar is not read, and its indicator is the value.
        (">-", ">-"),
        ("| # c", "|"),
        # A quote that is not closed is kept.
        ('"foo', '"foo'),
    ]:
        fields, _ = chart_utils.parse_chart_yaml("name: " + line + "\nversion: 1\n")
        asserts.equals(env, value, fields["name"], line)
        asserts.equals(env, "1", fields["version"], line)

    # An annotation value may have a comment as well.
    _, annotations = chart_utils.parse_chart_yaml("annotations:\n  licenses: MIT # SPDX\n")

    # buildifier: disable=attr-licenses
    asserts.equals(env, {"licenses": "MIT"}, annotations)

    # An empty value and a nested key do not set a field.
    fields, _ = chart_utils.parse_chart_yaml("name:\ndependencies:\n  version: 2\n")
    asserts.equals(env, {}, fields)

    return unittest.end(env)

parse_chart_yaml_test = unittest.make(_parse_chart_yaml_test_impl)

def _is_chart_name_and_version_test_impl(ctx):
    env = unittest.begin(ctx)

    # Valid as a name and as a version.
    for value in ["cert-manager", "vault-operator", "a.b_c", "Foo1", "1", "v1.19.4", "1.21.0-beta.0"]:
        asserts.true(env, chart_utils.is_chart_name(value), value)
        asserts.true(env, chart_utils.is_chart_version(value), value)

    # `+` marks build metadata in a version and cannot be in a name.
    asserts.true(env, chart_utils.is_chart_version("1.0.0+build.5"))
    asserts.false(env, chart_utils.is_chart_name("1.0.0+build.5"))

    for value in [None, "", ">-", "foo bar", 'foo"x', "foo # c", "foo\nbar", "a/b", "a:b", "a\\b"]:
        asserts.false(env, chart_utils.is_chart_name(value), str(value))
        asserts.false(env, chart_utils.is_chart_version(value), str(value))
    return unittest.end(env)

is_chart_name_and_version_test = unittest.make(_is_chart_name_and_version_test_impl)

def _chart_sha256_test_impl(ctx):
    env = unittest.begin(ctx)

    # A digest in the tag is used as it is, with no lookup and no fact.
    calls = []
    lookup = lambda url: calls.append(url) or _OTHER_SHA
    chart = chart_utils.chart_sha256(_SHA, _URL, {_URL: _OTHER_SHA}, lookup)
    asserts.equals(env, _SHA, chart.sha256)
    asserts.false(env, chart.is_fact)
    asserts.equals(env, [], calls)

    # A stored digest is used with no lookup, and stays in the facts.
    calls = []
    chart = chart_utils.chart_sha256("", _URL, {_URL: _SHA}, lookup)
    asserts.equals(env, _SHA, chart.sha256)
    asserts.true(env, chart.is_fact)
    asserts.equals(env, [], calls)

    # Without a stored digest, the registry result is used and becomes a fact.
    calls = []
    chart = chart_utils.chart_sha256("", _URL, {}, lookup)
    asserts.equals(env, _OTHER_SHA, chart.sha256)
    asserts.true(env, chart.is_fact)
    asserts.equals(env, [_URL], calls)

    # A stored value that is not a digest is looked up again.
    calls = []
    chart = chart_utils.chart_sha256("", _URL, {_URL: "not-a-digest"}, lookup)
    asserts.equals(env, _OTHER_SHA, chart.sha256)
    asserts.equals(env, [_URL], calls)

    # A digest stored for another chart is not used.
    calls = []
    chart = chart_utils.chart_sha256("", _URL, {"oci://quay.io/other/chart:1.0.0": _SHA}, lookup)
    asserts.equals(env, _OTHER_SHA, chart.sha256)
    asserts.equals(env, [_URL], calls)

    return unittest.end(env)

chart_sha256_test = unittest.make(_chart_sha256_test_impl)

def chart_utils_test_suite(name):
    unittest.suite(
        name,
        is_sha256_test,
        parse_url_test,
        parse_chart_yaml_test,
        is_chart_name_and_version_test,
        chart_sha256_test,
    )

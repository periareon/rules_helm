"""Unit tests for the chart import helpers."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")

# buildifier: disable=bzl-visibility
load("//helm/private:chart_utils.bzl", "chart_utils")

_SHA = "d0c202f57b8653eb957fb5b2f9472c1b11cf6b51acc5c777e4b824f7b5a9ea87"
_OTHER_SHA = "9abd372c9d843b974d918442cd0e68c9669f57d8630566ce74dfaf63447c282a"
_URL = "oci://quay.io/jetstack/charts/cert-manager:1.19.4"

def _split_chart_file_test_impl(ctx):
    env = unittest.begin(ctx)
    for chart_file, expected in {
        "app-2-1.0.0.tgz": ("app-2", "1.0.0"),
        "cert-manager-1.21.0-beta.0.tgz": ("cert-manager", "1.21.0-beta.0"),
        "foo-1.0.0-rc.1.tgz": ("foo", "1.0.0-rc.1"),
        "foo-1.tgz": ("foo", "1"),
        "redis-21.2.5.tgz": ("redis", "21.2.5"),
        "trust-manager-v0.24.0.tgz": ("trust-manager", "v0.24.0"),
        "vault-operator-1.23.0.tgz": ("vault-operator", "1.23.0"),
    }.items():
        asserts.equals(env, expected, chart_utils.split_chart_file(chart_file), chart_file)
    return unittest.end(env)

split_chart_file_test = unittest.make(_split_chart_file_test_impl)

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

def _is_chart_url_test_impl(ctx):
    env = unittest.begin(ctx)
    for url in [
        _URL,
        "oci://public.ecr.aws/karpenter/karpenter:1.9.0",
        "oci://localhost:5000/charts/app:1.0.0-rc.1",
    ]:
        asserts.true(env, chart_utils.is_chart_url(url), url)
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
        asserts.false(env, chart_utils.is_chart_url(url), url)
    return unittest.end(env)

is_chart_url_test = unittest.make(_is_chart_url_test_impl)

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
        split_chart_file_test,
        is_sha256_test,
        is_chart_url_test,
        chart_sha256_test,
    )

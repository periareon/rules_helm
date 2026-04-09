#!/usr/bin/env bash
# Validates OCI layout directory against the OCI Image Layout Specification.
# https://github.com/opencontainers/image-spec/blob/main/image-layout.md
set -euo pipefail

# The layout directory is a sibling of the digest file with .oci_layout suffix
LAYOUT="${DIGEST_FILE%.digest}.oci_layout"

FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }

# --- oci-layout file ---
if [ -f "$LAYOUT/oci-layout" ]; then
    pass "oci-layout file exists"
else
    fail "oci-layout file missing (REQUIRED per spec)"
fi

VERSION=$(python3 -c "import json; print(json.load(open('$LAYOUT/oci-layout'))['imageLayoutVersion'])")
if [ "$VERSION" = "1.0.0" ]; then
    pass "imageLayoutVersion is 1.0.0"
else
    fail "imageLayoutVersion is '$VERSION', expected '1.0.0'"
fi

# --- index.json ---
if [ -f "$LAYOUT/index.json" ]; then
    pass "index.json exists"
else
    fail "index.json missing (REQUIRED per spec)"
fi

SCHEMA_VERSION=$(python3 -c "import json; print(json.load(open('$LAYOUT/index.json'))['schemaVersion'])")
if [ "$SCHEMA_VERSION" = "2" ]; then
    pass "index.json schemaVersion is 2"
else
    fail "index.json schemaVersion is '$SCHEMA_VERSION', expected 2"
fi

INDEX_MEDIA=$(python3 -c "import json; print(json.load(open('$LAYOUT/index.json')).get('mediaType', ''))")
if [ "$INDEX_MEDIA" = "application/vnd.oci.image.index.v1+json" ]; then
    pass "index.json mediaType is correct"
else
    fail "index.json mediaType is '$INDEX_MEDIA', expected 'application/vnd.oci.image.index.v1+json'"
fi

# --- blobs directory ---
if [ -d "$LAYOUT/blobs" ]; then
    pass "blobs/ directory exists"
else
    fail "blobs/ directory missing (REQUIRED per spec)"
fi

if [ -d "$LAYOUT/blobs/sha256" ]; then
    pass "blobs/sha256/ directory exists"
else
    fail "blobs/sha256/ directory missing"
fi

# --- Manifest descriptor in index.json ---
MANIFEST_MEDIA=$(python3 -c "import json; print(json.load(open('$LAYOUT/index.json'))['manifests'][0]['mediaType'])")
if [ "$MANIFEST_MEDIA" = "application/vnd.oci.image.manifest.v1+json" ]; then
    pass "manifest descriptor mediaType is correct"
else
    fail "manifest descriptor mediaType is '$MANIFEST_MEDIA'"
fi

MANIFEST_DIGEST=$(python3 -c "import json; print(json.load(open('$LAYOUT/index.json'))['manifests'][0]['digest'])")
MANIFEST_HEX="${MANIFEST_DIGEST#sha256:}"
if [ -f "$LAYOUT/blobs/sha256/$MANIFEST_HEX" ]; then
    pass "manifest blob exists at blobs/sha256/$MANIFEST_HEX"
else
    fail "manifest blob missing: blobs/sha256/$MANIFEST_HEX"
fi

MANIFEST_SIZE=$(python3 -c "import json; print(json.load(open('$LAYOUT/index.json'))['manifests'][0]['size'])")
ACTUAL_SIZE=$(wc -c < "$LAYOUT/blobs/sha256/$MANIFEST_HEX" | tr -d ' ')
if [ "$MANIFEST_SIZE" = "$ACTUAL_SIZE" ]; then
    pass "manifest size matches ($ACTUAL_SIZE bytes)"
else
    fail "manifest size mismatch: index says $MANIFEST_SIZE, actual $ACTUAL_SIZE"
fi

# --- Blob content integrity (spec: content MUST match digest) ---
for blob in "$LAYOUT/blobs/sha256/"*; do
    expected=$(basename "$blob")
    actual=$(shasum -a 256 "$blob" | awk '{print $1}')
    if [ "$expected" = "$actual" ]; then
        pass "blob $expected content matches digest"
    else
        fail "blob $expected: expected sha256=$expected, got $actual"
    fi
done

# --- Manifest references valid blobs ---
MANIFEST_BLOB="$LAYOUT/blobs/sha256/$MANIFEST_HEX"

CONFIG_DIGEST=$(python3 -c "import json; print(json.load(open('$MANIFEST_BLOB'))['config']['digest'].split(':')[1])")
if [ -f "$LAYOUT/blobs/sha256/$CONFIG_DIGEST" ]; then
    pass "config blob exists"
else
    fail "config blob missing: blobs/sha256/$CONFIG_DIGEST"
fi

CONFIG_MEDIA=$(python3 -c "import json; print(json.load(open('$MANIFEST_BLOB'))['config']['mediaType'])")
if [ "$CONFIG_MEDIA" = "application/vnd.cncf.helm.config.v1+json" ]; then
    pass "config mediaType is Helm config type"
else
    fail "config mediaType is '$CONFIG_MEDIA', expected 'application/vnd.cncf.helm.config.v1+json'"
fi

LAYER_DIGEST=$(python3 -c "import json; print(json.load(open('$MANIFEST_BLOB'))['layers'][0]['digest'].split(':')[1])")
if [ -f "$LAYOUT/blobs/sha256/$LAYER_DIGEST" ]; then
    pass "chart layer blob exists"
else
    fail "chart layer blob missing: blobs/sha256/$LAYER_DIGEST"
fi

LAYER_MEDIA=$(python3 -c "import json; print(json.load(open('$MANIFEST_BLOB'))['layers'][0]['mediaType'])")
if [ "$LAYER_MEDIA" = "application/vnd.cncf.helm.chart.content.v1.tar+gzip" ]; then
    pass "layer mediaType is Helm chart type"
else
    fail "layer mediaType is '$LAYER_MEDIA', expected 'application/vnd.cncf.helm.chart.content.v1.tar+gzip'"
fi

# --- Annotations (deterministic, no timestamp) ---
HAS_TITLE=$(python3 -c "import json; m=json.load(open('$MANIFEST_BLOB')); print('org.opencontainers.image.title' in m.get('annotations', {}))")
if [ "$HAS_TITLE" = "True" ]; then
    pass "manifest has title annotation"
else
    fail "manifest missing title annotation"
fi

HAS_VERSION=$(python3 -c "import json; m=json.load(open('$MANIFEST_BLOB')); print('org.opencontainers.image.version' in m.get('annotations', {}))")
if [ "$HAS_VERSION" = "True" ]; then
    pass "manifest has version annotation"
else
    fail "manifest missing version annotation"
fi

HAS_CREATED=$(python3 -c "import json; m=json.load(open('$MANIFEST_BLOB')); print('org.opencontainers.image.created' in m.get('annotations', {}))")
if [ "$HAS_CREATED" = "False" ]; then
    pass "manifest does NOT have created timestamp (deterministic)"
else
    fail "manifest has created timestamp — makes digest non-deterministic"
fi

# --- Summary ---
if [ "$FAIL" -eq 0 ]; then
    echo ""
    echo "All OCI layout spec checks passed."
else
    echo ""
    echo "Some checks FAILED."
    exit 1
fi

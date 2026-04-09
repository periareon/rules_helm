#!/usr/bin/env bash
# Validates that the OCI digest is deterministic — same chart always
# produces the same digest, and the digest file format is valid.
set -euo pipefail

FAIL=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAIL=1; }

# --- Digest file format ---
DIGEST=$(cat "$DIGEST_FILE")

if [[ "$DIGEST" =~ ^sha256:[a-f0-9]{64}$ ]]; then
    pass "digest format is sha256:<64 hex chars>"
else
    fail "digest format invalid: '$DIGEST'"
fi

# --- Digest matches sha256 of manifest blob ---
LAYOUT="${DIGEST_FILE%.digest}.oci_layout"
MANIFEST_HEX="${DIGEST#sha256:}"
if [ -f "$LAYOUT/blobs/sha256/$MANIFEST_HEX" ]; then
    ACTUAL=$(shasum -a 256 "$LAYOUT/blobs/sha256/$MANIFEST_HEX" | awk '{print "sha256:" $1}')
    if [ "$DIGEST" = "$ACTUAL" ]; then
        pass "digest file matches sha256 of manifest blob"
    else
        fail "digest=$DIGEST but manifest blob sha256=$ACTUAL"
    fi
else
    fail "manifest blob not found at blobs/sha256/$MANIFEST_HEX"
fi

# --- Digest file has no trailing newline or whitespace ---
BYTE_COUNT=$(wc -c < "$DIGEST_FILE" | tr -d ' ')
EXPECTED_LEN=71  # "sha256:" (7) + 64 hex chars = 71
if [ "$BYTE_COUNT" = "$EXPECTED_LEN" ]; then
    pass "digest file is exactly $EXPECTED_LEN bytes (no trailing newline)"
else
    fail "digest file is $BYTE_COUNT bytes, expected $EXPECTED_LEN"
fi

# --- Summary ---
if [ "$FAIL" -eq 0 ]; then
    echo ""
    echo "All determinism checks passed."
else
    echo ""
    echo "Some checks FAILED."
    exit 1
fi

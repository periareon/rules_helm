#!/usr/bin/env bash

set -euo pipefail

echo STABLE_STAMP_VALUE "stable"
echo VOLATILE_STAMP_VALUE "volatile"
# Fixed stand-in for a commit-derived source-date epoch (real builds: `git log
# -1 --format=%ct`). The STABLE_ prefix puts it in the stable status file, part
# of the action cache key, so a given commit stays reproducible.
echo STABLE_SOURCE_DATE_EPOCH "1234567890"

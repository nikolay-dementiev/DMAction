#!/bin/bash
#
# Checks what a consumer of the package gets, and what the repository's own tooling does
# on the machine of whoever runs it.
#
#   Scripts/check-manifest.sh
#
# 1. No tracked file under Examples/ deletes a directory tree. The example's Pod helper
#    used to delete the Xcode DerivedData folder of the whole machine on every install.
#    This is a text search: it catches that spelling again, it does not prove that a
#    script has no side effect.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILED=0

cd "$ROOT"

# 1. The example's tooling.
DELETES="$(git grep -nE 'rm[[:space:]]+-[a-zA-Z]*[rR]|FileUtils\.(rm_rf|rm_r|remove_dir|remove_entry)' -- Examples || true)"
if [ -n "$DELETES" ]; then
    echo "check-manifest: the example's tooling deletes directory trees:" >&2
    echo "$DELETES" | cut -c1-160 | sed 's/^/  /' >&2
    FAILED=1
else
    echo "check-manifest: no recursive delete in the example's tooling."
fi

exit "$FAILED"

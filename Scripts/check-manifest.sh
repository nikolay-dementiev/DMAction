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
# 2. Fixtures/Consumer builds. It uses every released public declaration and the shapes
#    the downstream package relies on, so if it stops building, a consumer's code stops
#    building.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$ROOT/.build/check-manifest"
FAILED=0

mkdir -p "$WORK"
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

# 2. The consumer fixture. xcodebuild finds a package only in the current directory.
#    The plugin validation is skipped only as long as the manifest still carries the lint
#    plugin: a consumer has to do the same today.
DERIVED="$(mktemp -d "$WORK/DerivedData.XXXXXX")"
cd "$ROOT/Fixtures/Consumer"
if xcodebuild build \
    -scheme Consumer \
    -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED" \
    -skipPackagePluginValidation \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
    > "$WORK/consumer-build.log" 2>&1; then
    echo "check-manifest: Fixtures/Consumer builds against this checkout."
else
    echo "check-manifest: Fixtures/Consumer does not build. See ${WORK#"$ROOT"/}/consumer-build.log" >&2
    grep -E "error:" "$WORK/consumer-build.log" | sort -u | cut -c1-240 | head -20 >&2 || true
    FAILED=1
fi
cd "$ROOT"

exit "$FAILED"

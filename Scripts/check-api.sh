#!/bin/bash
#
# Compares the public interface of the library with the committed baseline.
#
#   Scripts/check-api.sh            compare, exit 1 on any difference
#   Scripts/check-api.sh --update   rewrite the baseline from the current sources
#
# Any difference fails. A removed or changed line is a break of the public contract.
# An added line is new public API: run with --update and commit the baseline together
# with the change, so the whole API delta is readable in the diff of one file.
#
# The baseline sees declarations and default values. It does not see behaviour: an
# ordering, a count or the value an action reports is pinned by the tests.
#
# The interface text depends on the compiler and the SDK. CI runs this check on one
# pinned Xcode; after a toolchain change the baseline may need --update with no API change.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="DMAction"
BASELINE="$ROOT/Fixtures/API/public-interface.txt"
WORK="$ROOT/.build/check-api"
INTERFACE="$WORK/$MODULE.swiftinterface"
CURRENT="$WORK/public-interface.txt"

mkdir -p "$WORK"

SOURCES=()
while IFS= read -r file; do
    SOURCES+=("$file")
done < <(find "$ROOT/Sources/$MODULE" -name '*.swift' | sort)

# The compiler is called directly, for the platform the package is released for. The
# module and its protocol share the name DMAction, so qualified names in the emitted
# interface are ambiguous to the interface verifier, which a build through xcodebuild
# always runs. The emitted text is still the complete interface.
if ! xcrun --sdk iphonesimulator swiftc \
    -target arm64-apple-ios17.0-simulator \
    -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
    -module-name "$MODULE" \
    -package-name "$MODULE" \
    -swift-version 6 \
    -enable-library-evolution \
    -emit-module -emit-module-path "$WORK/$MODULE.swiftmodule" \
    -emit-module-interface-path "$INTERFACE" \
    -no-verify-emitted-module-interface \
    "${SOURCES[@]}" \
    > "$WORK/swiftc.log" 2>&1; then
    echo "check-api: the library does not compile. See ${WORK#"$ROOT"/}/swiftc.log" >&2
    grep -E "error:" "$WORK/swiftc.log" | sort -u | head -20 >&2 || true
    exit 2
fi

# Header comments carry the compiler version and flags; imports are not API.
grep -v -E '^(//|import )' "$INTERFACE" > "$CURRENT"

if [ "${1:-}" = "--update" ]; then
    mkdir -p "$(dirname "$BASELINE")"
    cp "$CURRENT" "$BASELINE"
    echo "check-api: baseline updated: ${BASELINE#"$ROOT"/}"
    exit 0
fi

if [ ! -f "$BASELINE" ]; then
    echo "check-api: no baseline at ${BASELINE#"$ROOT"/}. Run with --update." >&2
    exit 2
fi

if diff -u "$BASELINE" "$CURRENT" > "$WORK/api.diff"; then
    echo "check-api: the public interface matches the baseline."
    exit 0
fi

echo "check-api: the public interface differs from the baseline." >&2
echo "  '-' lines were removed or changed: that breaks the public contract." >&2
echo "  '+' lines are new public API: run Scripts/check-api.sh --update and commit the baseline." >&2
cat "$WORK/api.diff" >&2
exit 1

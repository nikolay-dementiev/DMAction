#!/bin/bash
#
# Compares the public interface of the library with the committed baseline.
#
#   Scripts/check-api.sh               compare, exit 1 on any difference
#   Scripts/check-api.sh --update      rewrite the baseline from the current sources
#   Scripts/check-api.sh --self-test   run the normalisation on the cases in
#                                      Fixtures/API/normalizer, no compiler needed
#
# Any difference fails. A removed or changed line is a break of the public contract.
# An added line is new public API: run with --update and commit the baseline together
# with the change, so the whole API delta is readable in the diff of one file.
#
# The interface text depends on the compiler and the SDK. CI runs this check on one
# pinned Xcode; after a toolchain change the baseline may need --update with no API change.
#
# Exit codes: 0 the same interface, 1 a different interface, 2 the check could not run.

set -euo pipefail

# ==== Settings of this repository =======================================================
# The packages DMAction, DMVariableBlurView and DMUnLoader share this script. Only this
# block differs between them. Everything below the end marker is identical in the three:
# a change there is made in the copy of DMVariableBlurView and synced to the other two.

# The module whose public interface is checked.
MODULE="DMAction"
# The directory the manifest compiles for that module, relative to the repository root.
SOURCE_DIR="Sources"
# The language mode and the upcoming features the manifest sets for the module.
SWIFT_FLAGS=(-swift-version 6)
# "yes" to emit the interface with library evolution, "no" without it.
LIBRARY_EVOLUTION="yes"
# Modules of package dependencies that the module imports, compiled first and in this
# order. One entry per module: "<module>|<source directory>|<compiler flags>", where the
# flags mirror the manifest of the dependency, including its -package-name.
DEPENDENCIES=()

# ==== End of the settings ===============================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASELINE="$ROOT/Fixtures/API/public-interface.txt"
WORK="$ROOT/.build/check-api"
INTERFACE="$WORK/$MODULE.swiftinterface"
CURRENT="$WORK/public-interface.txt"

mkdir -p "$WORK"

# Header comments carry the compiler version and flags; imports are not API; an empty
# line only marks where a source file ended. The compiler emits declarations in the
# order of the source files, so the top-level declarations are sorted: moving a type to
# another file must not look like an API change. An attribute that the compiler prints
# on a line of its own, such as @available, stays with the declaration below it, and a
# compiler condition (#if ... #endif) stays one block with what it guards: moving either
# to another declaration is an API change.
normalize() {
    { grep -v -E '^(//|import |$)' "$1" || true; } | python3 -c '
import sys

def attributes_only(line):
    position, end = 0, len(line)
    while position < end:
        if line[position].isspace():
            position += 1
            continue
        if line[position] != "@":
            return False
        position += 1
        while position < end and (line[position].isalnum() or line[position] in "_."):
            position += 1
        if position < end and line[position] == "(":
            # Parentheses inside a string literal, such as a message, do not count.
            depth, in_string = 0, False
            while position < end:
                character = line[position]
                if in_string:
                    if character == "\\":
                        position += 1
                    elif character == "\"":
                        in_string = False
                elif character == "\"":
                    in_string = True
                elif character == "(":
                    depth += 1
                elif character == ")":
                    depth -= 1
                position += 1
                if depth == 0:
                    break
    return True

blocks, current, conditions = [], [], 0
for line in sys.stdin.read().splitlines():
    starts_declaration = bool(line) and not line[0].isspace() and line != "}"
    if starts_declaration and current and conditions == 0 and not all(attributes_only(held) for held in current):
        blocks.append("\n".join(current))
        current = []
    current.append(line)
    directive = line.lstrip()
    if directive.startswith("#if"):
        conditions += 1
    elif directive.startswith("#endif"):
        conditions -= 1
if current:
    blocks.append("\n".join(current))
print("\n".join(sorted(blocks)))
'
}

# Each case holds two interface texts and says whether they must normalise to the same
# text. A change to normalize() that hides an API change, or reports one that is not
# there, fails one of them.
if [ "${1:-}" = "--self-test" ]; then
    CASES="$ROOT/Fixtures/API/normalizer"
    FAILED=0
    for CASE in "$CASES"/*.txt; do
        NAME="$(basename "$CASE" .txt)"
        EXPECTED="$(sed -n 's/^# expect: //p' "$CASE")"
        awk '/^--- A ---$/ { part = "A"; next } /^--- B ---$/ { part = "B"; next } part == "A"' "$CASE" > "$WORK/case-a.txt"
        awk '/^--- B ---$/ { part = "B"; next } part == "B"' "$CASE" > "$WORK/case-b.txt"
        if ! normalize "$WORK/case-a.txt" > "$WORK/case-a.normalized" || ! normalize "$WORK/case-b.txt" > "$WORK/case-b.normalized"; then
            echo "check-api: FAIL $NAME: the normalisation stopped with an error" >&2
            FAILED=1
            continue
        fi
        if cmp -s "$WORK/case-a.normalized" "$WORK/case-b.normalized"; then ACTUAL="same"; else ACTUAL="different"; fi
        if [ "$ACTUAL" = "$EXPECTED" ]; then
            echo "check-api: ok   $NAME"
        else
            echo "check-api: FAIL $NAME: expected $EXPECTED, the normalised texts are $ACTUAL" >&2
            FAILED=1
        fi
    done
    exit "$FAILED"
fi

# The files of a module are passed in one fixed order. A plain sort follows the locale
# of the machine, and the order of the files is the order in which the compiler emits
# the declarations.
swift_sources() {
    find "$ROOT/$1" -name '*.swift' | LC_ALL=C sort
}

# The compiler is called for the iOS simulator, a platform the packages are released
# for. It is called directly, because a module that shares its name with one of its
# types cannot pass the interface verifier that a build through xcodebuild always runs.
SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
TARGET="arm64-apple-ios17.0-simulator"

# Bash 3.2, the version macOS ships, treats an empty array as unbound under set -u, hence
# the ${name[@]+"${name[@]}"} form for arrays that may be empty.
for DEPENDENCY in ${DEPENDENCIES[@]+"${DEPENDENCIES[@]}"}; do
    DEPENDENCY_MODULE="${DEPENDENCY%%|*}"
    REST="${DEPENDENCY#*|}"
    DEPENDENCY_DIR="${REST%%|*}"
    read -r -a DEPENDENCY_FLAGS <<< "${REST#*|}"
    DEPENDENCY_SOURCES=()
    while IFS= read -r file; do
        DEPENDENCY_SOURCES+=("$file")
    done < <(swift_sources "$DEPENDENCY_DIR")
    if [ "${#DEPENDENCY_SOURCES[@]}" -eq 0 ]; then
        echo "check-api: no Swift source in $DEPENDENCY_DIR for the dependency $DEPENDENCY_MODULE." >&2
        exit 2
    fi
    if ! xcrun --sdk iphonesimulator swiftc \
        -target "$TARGET" -sdk "$SDK_PATH" -I "$WORK" \
        -module-name "$DEPENDENCY_MODULE" \
        ${DEPENDENCY_FLAGS[@]+"${DEPENDENCY_FLAGS[@]}"} \
        -emit-module -emit-module-path "$WORK/$DEPENDENCY_MODULE.swiftmodule" \
        "${DEPENDENCY_SOURCES[@]}" \
        > "$WORK/swiftc-$DEPENDENCY_MODULE.log" 2>&1; then
        echo "check-api: the dependency $DEPENDENCY_MODULE does not compile. See ${WORK#"$ROOT"/}/swiftc-$DEPENDENCY_MODULE.log" >&2
        grep -E "error:" "$WORK/swiftc-$DEPENDENCY_MODULE.log" | sort -u | head -20 >&2 || true
        exit 2
    fi
done

SOURCES=()
while IFS= read -r file; do
    SOURCES+=("$file")
done < <(swift_sources "$SOURCE_DIR")
if [ "${#SOURCES[@]}" -eq 0 ]; then
    echo "check-api: no Swift source in $SOURCE_DIR. Check SOURCE_DIR in the settings." >&2
    exit 2
fi

EVOLUTION_FLAGS=()
if [ "$LIBRARY_EVOLUTION" = "yes" ]; then
    EVOLUTION_FLAGS=(-enable-library-evolution)
fi

if ! xcrun --sdk iphonesimulator swiftc \
    -target "$TARGET" -sdk "$SDK_PATH" -I "$WORK" \
    -module-name "$MODULE" \
    -package-name "$MODULE" \
    "${SWIFT_FLAGS[@]}" \
    ${EVOLUTION_FLAGS[@]+"${EVOLUTION_FLAGS[@]}"} \
    -emit-module -emit-module-path "$WORK/$MODULE.swiftmodule" \
    -emit-module-interface-path "$INTERFACE" \
    -no-verify-emitted-module-interface \
    "${SOURCES[@]}" \
    > "$WORK/swiftc.log" 2>&1; then
    echo "check-api: the library does not compile. See ${WORK#"$ROOT"/}/swiftc.log" >&2
    grep -E "error:" "$WORK/swiftc.log" | sort -u | head -20 >&2 || true
    exit 2
fi

normalize "$INTERFACE" > "$CURRENT"

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

# The baseline goes through the same normalization, so the comparison does not depend on
# the order of the declarations in either file.
normalize "$BASELINE" > "$WORK/baseline.txt"

if diff -u --label "$(basename "$BASELINE")" --label "current interface" "$WORK/baseline.txt" "$CURRENT" > "$WORK/api.diff"; then
    echo "check-api: the public interface matches the baseline."
    exit 0
fi

echo "check-api: the public interface differs from the baseline." >&2
echo "  '-' lines were removed or changed: that breaks the public contract." >&2
echo "  '+' lines are new public API: run Scripts/check-api.sh --update and commit the baseline." >&2
cat "$WORK/api.diff" >&2
exit 1

#!/bin/bash
#
# Lints the repository with the SwiftLint version pinned in .swiftlint.yml.
#
#   Scripts/lint.sh                         lint; a warning fails the run
#   Scripts/lint.sh --analyze <build log>   also run the analyzer rules, which need the
#                                           compiler invocations of an xcodebuild log, from
#                                           a build whose DerivedData is still on disk
#
# The tool is fetched once into .build/tools and checked against the pinned checksum
# before it is unpacked. Nothing is installed or upgraded on the machine.

set -euo pipefail

# A mistyped option would otherwise lint without the analyzer and still pass.
case "${1:-}" in
    "" | --analyze) ;;
    *)
        echo "usage: Scripts/lint.sh [--analyze <xcodebuild log>]" >&2
        exit 2
        ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(sed -n 's/^swiftlint_version: *//p' "$ROOT/.swiftlint.yml")"
# SHA-256 of portable_swiftlint.zip of that release. It changes together with the version.
CHECKSUM="c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0"
TOOLS="$ROOT/.build/tools/swiftlint-$VERSION"
SWIFTLINT="$TOOLS/swiftlint"

if [ -z "$VERSION" ]; then
    echo "lint: .swiftlint.yml does not pin swiftlint_version" >&2
    exit 2
fi

if [ ! -x "$SWIFTLINT" ]; then
    mkdir -p "$TOOLS"
    ARCHIVE="$TOOLS/portable_swiftlint.zip"
    if [ ! -f "$ARCHIVE" ]; then
        # Fetched under another name, so an interrupted transfer never passes for the archive.
        curl --fail --silent --show-error --location --retry 3 \
            "https://github.com/realm/SwiftLint/releases/download/$VERSION/portable_swiftlint.zip" \
            --output "$ARCHIVE.part"
        mv "$ARCHIVE.part" "$ARCHIVE"
    fi
    ACTUAL="$(shasum -a 256 "$ARCHIVE" | cut -d ' ' -f 1)"
    if [ "$ACTUAL" != "$CHECKSUM" ]; then
        # A wrong archive must not block every later run: the next one fetches it again.
        rm -f "$ARCHIVE"
        echo "lint: the SwiftLint $VERSION archive had checksum $ACTUAL, expected $CHECKSUM. It was removed." >&2
        exit 2
    fi
    unzip -q -o "$ARCHIVE" swiftlint -d "$TOOLS"
fi

cd "$ROOT"
"$SWIFTLINT" lint --strict --quiet

ANALYZED=""
if [ "${1:-}" = "--analyze" ]; then
    # Not --quiet: the summary names how many files were analyzed. A log without compiler
    # invocations, or one whose file lists left with their DerivedData, gets no file analyzed
    # and SwiftLint still exits 0.
    STATUS=0
    REPORT="$("$SWIFTLINT" analyze --strict --compiler-log-path "${2:?give the path of an xcodebuild log}" 2>&1)" \
        || STATUS=$?
    if [ "$STATUS" -ne 0 ]; then
        printf '%s\n' "$REPORT" >&2
        exit "$STATUS"
    fi
    FILES="$(printf '%s\n' "$REPORT" | sed -n 's/^Done analyzing!.* in \([0-9][0-9]*\) files*\.$/\1/p')"
    if [ -z "$FILES" ] || [ "$FILES" -eq 0 ]; then
        printf '%s\n' "$REPORT" >&2
        echo "lint: the analyzer read no Swift file. It needs the log of a build whose DerivedData is still on disk." >&2
        exit 2
    fi
    ANALYZED=", the analyzer read $FILES files"
fi

echo "lint: no violations (SwiftLint $("$SWIFTLINT" version))$ANALYZED."

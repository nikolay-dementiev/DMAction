#!/bin/bash
#
# Compiles every Swift block of README.md against this checkout.
#
#   Scripts/check-readme-snippets.sh
#
# Each block is compiled in a context of its own, so that a block cannot use a name another
# block declares and one broken block cannot hide behind another:
#
# - A block that contains `Package(` is a package manifest. It must be complete, from its
#   tools version on, and SwiftPM evaluates it.
# - A block that imports UIKit or SwiftUI is a target of its own in a package for iOS, built
#   for the simulator.
# - Any other block is the main file of a command-line tool, built for this Mac.
#
# The packages are generated under .build/check-readme-snippets. They depend on this
# checkout by path, the way Fixtures/Consumer does. A warning in a block fails the check too.
# It is read from the build log: Xcode builds the dependency with its warnings suppressed,
# which conflicts with warnings as errors for the whole build.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
README="$ROOT/README.md"
WORK="$ROOT/.build/check-readme-snippets"
# The build folders live outside the generated packages: Xcode may still write to its
# DerivedData for a moment after a build, so the folder could not always be deleted. The
# blocks are written anew on every run, so they are compiled again, warnings included.
TOOLS_BUILD="$ROOT/.build/check-readme-snippets-tools"
IOS_DERIVED_DATA="$ROOT/.build/check-readme-snippets-ios"

rm -rf "$WORK"
mkdir -p "$WORK"

# Writes one file per block and prints its kind and the README line it starts on.
python3 - "$README" "$WORK" > "$WORK/blocks.txt" <<'PY'
import os
import re
import sys

readme, work = sys.argv[1], sys.argv[2]
lines = open(readme, encoding="utf-8").read().split("\n")
block, start, number = None, 0, 0
for index, line in enumerate(lines, start=1):
    if block is None:
        if line.strip() == "```swift":
            block, start = [], index + 1
    elif line.strip() == "```":
        number += 1
        text = "\n".join(block) + "\n"
        if "Package(" in text:
            kind = "manifest"
        elif re.search(r"^import (UIKit|SwiftUI)$", text, re.MULTILINE):
            kind = "ios"
        else:
            kind = "tool"
        name = f"Snippet{number:02d}"
        os.makedirs(os.path.join(work, "blocks"), exist_ok=True)
        with open(os.path.join(work, "blocks", f"{name}.swift"), "w", encoding="utf-8") as out:
            out.write(text)
        print(kind, name, start)
        block = None
    else:
        block.append(line)
if block is not None:
    sys.exit(f"README.md: the Swift block that starts on line {start} is not closed")
PY

if [ ! -s "$WORK/blocks.txt" ]; then
    echo "check-readme-snippets: README.md has no Swift block." >&2
    exit 2
fi

FAILED=0
TOOLS=()
IOS=()
while read -r KIND NAME LINE; do
    echo "$NAME README.md:$LINE" >> "$WORK/lines.txt"
    case "$KIND" in
        manifest)
            mkdir -p "$WORK/$NAME"
            cp "$WORK/blocks/$NAME.swift" "$WORK/$NAME/Package.swift"
            if ! swift package dump-package --package-path "$WORK/$NAME" > "$WORK/$NAME.log" 2>&1; then
                echo "check-readme-snippets: the manifest at README.md:$LINE does not evaluate:" >&2
                sed 's/^/  /' "$WORK/$NAME.log" | head -20 >&2
                FAILED=1
            fi
            ;;
        tool)
            mkdir -p "$WORK/tools/Sources/$NAME"
            cp "$WORK/blocks/$NAME.swift" "$WORK/tools/Sources/$NAME/main.swift"
            TOOLS+=("$NAME")
            ;;
        ios)
            mkdir -p "$WORK/ios/Sources/$NAME"
            cp "$WORK/blocks/$NAME.swift" "$WORK/ios/Sources/$NAME/$NAME.swift"
            IOS+=("$NAME")
            ;;
    esac
done < "$WORK/blocks.txt"

# The manifest of a generated package: one target per block, each depending on DMAction.
write_manifest() { # <folder> <platform line> <target kind> <product line> <names...>
    local folder="$1" platform="$2" kind="$3" product="$4"
    shift 4
    {
        echo "// swift-tools-version: 6.0"
        echo "import PackageDescription"
        echo "let package = Package("
        echo "    name: \"ReadmeSnippets\","
        echo "    platforms: [$platform],"
        if [ -n "$product" ]; then
            echo "    products: [$product],"
        fi
        echo "    dependencies: [.package(name: \"DMAction\", path: \"$ROOT\")],"
        echo "    targets: ["
        for name in "$@"; do
            echo "        .$kind(name: \"$name\", dependencies: [.product(name: \"DMAction\", package: \"DMAction\")]),"
        done
        echo "    ]"
        echo ")"
    } > "$folder/Package.swift"
}

report() { # <log> <what>
    echo "check-readme-snippets: $2 do not build:" >&2
    grep -E "error:" "$1" | sort -u | sed "s|$WORK/||; s/^/  /" | head -20 >&2
    echo "  Snippet numbers map to README lines in ${WORK#"$ROOT"/}/lines.txt" >&2
}

check_warnings() { # <log> <sources folder>
    local warnings
    warnings="$(grep -E "^$2/[^:]+:[0-9]+:[0-9]+: warning:" "$1" | sort -u || true)"
    if [ -n "$warnings" ]; then
        echo "check-readme-snippets: a block has a warning:" >&2
        local prefix="$WORK/"
        printf '%s\n' "${warnings//$prefix/}" | sed 's/^/  /' >&2
        echo "  Snippet numbers map to README lines in ${WORK#"$ROOT"/}/lines.txt" >&2
        FAILED=1
    fi
}

if [ "${#TOOLS[@]}" -gt 0 ]; then
    write_manifest "$WORK/tools" ".macOS(.v14)" executableTarget "" "${TOOLS[@]}"
    if swift build --package-path "$WORK/tools" --scratch-path "$TOOLS_BUILD" > "$WORK/tools.log" 2>&1; then
        check_warnings "$WORK/tools.log" "$WORK/tools/Sources"
    else
        report "$WORK/tools.log" "the blocks for a command-line tool"
        FAILED=1
    fi
fi

if [ "${#IOS[@]}" -gt 0 ]; then
    TARGET_LIST="$(printf '"%s", ' "${IOS[@]}")"
    write_manifest "$WORK/ios" ".iOS(.v17)" target ".library(name: \"ReadmeSnippets\", targets: [${TARGET_LIST%, }])" "${IOS[@]}"
    if (cd "$WORK/ios" && xcodebuild build \
            -scheme ReadmeSnippets \
            -destination 'generic/platform=iOS Simulator' \
            -derivedDataPath "$IOS_DERIVED_DATA") > "$WORK/ios.log" 2>&1; then
        check_warnings "$WORK/ios.log" "$WORK/ios/Sources"
    else
        report "$WORK/ios.log" "the blocks for iOS"
        FAILED=1
    fi
fi

if [ "$FAILED" -ne 0 ]; then
    exit 1
fi
echo "check-readme-snippets: $(wc -l < "$WORK/blocks.txt" | tr -d ' ') Swift blocks of README.md build:" \
    "$(grep -c '^manifest' "$WORK/blocks.txt" || true) manifest, ${#TOOLS[@]} for a command-line tool, ${#IOS[@]} for iOS."

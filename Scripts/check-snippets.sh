#!/bin/bash
#
# Compiles every Swift example of the documentation against this checkout: each ```swift
# block of a tracked Markdown file, the README and the documentation catalog included, and
# each ```swift block in a doc comment (///) of the library's sources.
#
#   Scripts/check-snippets.sh
#
# Each block is compiled in a context of its own, so that a block cannot use a name another
# block declares and one broken block cannot hide behind another. A block must compile as it
# is written, its imports included:
#
# - A block that contains `Package(` is a package manifest. It must be complete, from its
#   tools version on, and SwiftPM evaluates it. Scripts/check-manifest.sh also builds the
#   README's manifest against a tagged copy of the package.
# - A block that imports UIKit or SwiftUI is a target of its own in a package for iOS, built
#   for the simulator.
# - Any other block is the main file of a command-line tool, built for this Mac.
#
# The packages are generated under .build/check-snippets. They depend on this checkout by
# path, the way Fixtures/Consumer does. A warning in a block fails the check too. It is read
# from the build log: Xcode builds the dependency with its warnings suppressed, which
# conflicts with warnings as errors for the whole build.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$ROOT/.build/check-snippets"
# The build folders live outside the generated packages: Xcode may still write to its
# DerivedData for a moment after a build, so the folder could not always be deleted. The
# blocks are written anew on every run, so they are compiled again, warnings included.
TOOLS_BUILD="$ROOT/.build/check-snippets-tools"
IOS_DERIVED_DATA="$ROOT/.build/check-snippets-ios"

rm -rf "$WORK"
mkdir -p "$WORK"

# The files to read: the tracked Markdown files, and the Swift sources of the library. In a
# plain pathspec, * matches across folders.
(cd "$ROOT" && git ls-files -- '*.md' 'Sources/*.swift') > "$WORK/files.txt"

# Writes one file per block and prints its kind, its name and where it starts.
python3 - "$ROOT" "$WORK" "$WORK/files.txt" > "$WORK/blocks.txt" <<'PY'
import os
import re
import sys

root, work, files = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(os.path.join(work, "blocks"), exist_ok=True)
number = 0
for path in open(files, encoding="utf-8").read().split("\n"):
    if not path:
        continue
    doc_comment = path.endswith(".swift")
    lines = open(os.path.join(root, path), encoding="utf-8").read().split("\n")
    block, start = None, 0
    for index, line in enumerate(lines, start=1):
        if doc_comment:
            # Only the lines of a doc comment count, without the slashes and one space.
            match = re.match(r"^\s*/// ?(.*)$", line)
            if match is None:
                if block is not None:
                    sys.exit(f"check-snippets: {path}:{start - 1}: the Swift block of this doc comment is not closed")
                continue
            line = match.group(1)
        if block is None:
            if line.strip() == "```swift":
                block, start = [], index + 1
            elif re.match(r"^\s*(```|~~~)", line) and "swift" in line.lower():
                # A fence that may still be shown as Swift, but that this check would skip.
                sys.exit(f"check-snippets: {path}:{index}: write a Swift block's fence as ```swift, so that it is compiled")
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
            with open(os.path.join(work, "blocks", f"{name}.swift"), "w", encoding="utf-8") as out:
                out.write(text)
            print(kind, name, f"{path}:{start}")
            block = None
        else:
            block.append(line)
    if block is not None:
        sys.exit(f"check-snippets: {path}: the Swift block that starts on line {start} is not closed")
PY

if [ ! -s "$WORK/blocks.txt" ]; then
    echo "check-snippets: the documentation has no Swift block." >&2
    exit 2
fi

FAILED=0
TOOLS=()
IOS=()
while read -r KIND NAME WHERE; do
    echo "$NAME $WHERE" >> "$WORK/lines.txt"
    case "$KIND" in
        manifest)
            mkdir -p "$WORK/$NAME"
            cp "$WORK/blocks/$NAME.swift" "$WORK/$NAME/Package.swift"
            if ! swift package dump-package --package-path "$WORK/$NAME" > "$WORK/$NAME.log" 2>&1; then
                echo "check-snippets: the manifest at $WHERE does not evaluate:" >&2
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
        echo "    name: \"Snippets\","
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
    echo "check-snippets: $2 do not build:" >&2
    local errors
    errors="$(grep -E "error:" "$1" | sort -u | head -20 || true)"
    if [ -n "$errors" ]; then
        printf '%s\n' "$errors" | sed 's/^/  /' >&2
    else
        tail -15 "$1" | sed 's/^/  /' >&2
    fi
    echo "  Snippet numbers map to their files and lines in ${WORK#"$ROOT"/}/lines.txt" >&2
}

# The compiler may print a path other than this script's, a resolved symbolic link for one,
# so a warning is found by the generated name of its block, not by the path of the checkout.
check_warnings() { # <log>
    local warnings
    warnings="$(grep -E "/Sources/Snippet[0-9]+/[^:]+:[0-9]+:[0-9]+: warning:" "$1" | sort -u || true)"
    if [ -n "$warnings" ]; then
        echo "check-snippets: a block has a warning:" >&2
        printf '%s\n' "$warnings" | sed 's/^/  /' >&2
        echo "  Snippet numbers map to their files and lines in ${WORK#"$ROOT"/}/lines.txt" >&2
        FAILED=1
    fi
}

# No warning means something only if the log shows the block compiled in this run.
check_compiled() { # <log> <pattern with NAME> <names...>
    local log="$1" pattern="$2" name
    shift 2
    for name in "$@"; do
        if ! grep -qE "${pattern//NAME/$name}" "$log"; then
            echo "check-snippets: $name, $(grep "^$name " "$WORK/lines.txt" | cut -d ' ' -f 2), was not compiled in this run" >&2
            FAILED=1
        fi
    done
}

if [ "${#TOOLS[@]}" -gt 0 ]; then
    write_manifest "$WORK/tools" ".macOS(.v14)" executableTarget "" "${TOOLS[@]}"
    if swift build --package-path "$WORK/tools" --scratch-path "$TOOLS_BUILD" > "$WORK/tools.log" 2>&1; then
        check_compiled "$WORK/tools.log" "Compiling NAME main\.swift" "${TOOLS[@]}"
        check_warnings "$WORK/tools.log"
    else
        report "$WORK/tools.log" "the blocks for a command-line tool"
        FAILED=1
    fi
fi

if [ "${#IOS[@]}" -gt 0 ]; then
    TARGET_LIST="$(printf '"%s", ' "${IOS[@]}")"
    write_manifest "$WORK/ios" ".iOS(.v17)" target ".library(name: \"Snippets\", targets: [${TARGET_LIST%, }])" "${IOS[@]}"
    if (cd "$WORK/ios" && xcodebuild build \
            -scheme Snippets \
            -destination 'generic/platform=iOS Simulator' \
            -derivedDataPath "$IOS_DERIVED_DATA") > "$WORK/ios.log" 2>&1; then
        check_compiled "$WORK/ios.log" "^SwiftCompile .*/Sources/NAME/NAME\.swift" "${IOS[@]}"
        check_warnings "$WORK/ios.log"
    else
        report "$WORK/ios.log" "the blocks for iOS"
        FAILED=1
    fi
fi

if [ "$FAILED" -ne 0 ]; then
    exit 1
fi
FILES="$(cut -d ' ' -f 3 "$WORK/blocks.txt" | cut -d : -f 1 | sort -u | tr '\n' ' ')"
echo "check-snippets: $(wc -l < "$WORK/blocks.txt" | tr -d ' ') Swift blocks build," \
    "$(grep -c '^manifest' "$WORK/blocks.txt" || true) manifest, ${#TOOLS[@]} for a command-line tool, ${#IOS[@]} for iOS," \
    "from ${FILES% }."

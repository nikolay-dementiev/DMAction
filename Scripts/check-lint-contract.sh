#!/bin/bash
#
# Proves that the lint rules of this repository fire. SwiftLint reports nothing for a rule that
# never matches, so a rule that stopped matching (a mistyped regular expression, a changed include
# pattern, a default that exempts a call) looks the same as a clean tree.
#
#   Scripts/check-lint-contract.sh
#
# Each file of Fixtures/Lint is a text file of Swift lines. The script copies the fixtures into a
# scratch copy of the package layout, lints them with the SwiftLint pinned in .swiftlint.yml and
# with the .swiftlint.yml of the repository, unchanged, and compares, line by line, the
# diagnostics of the rules in RULES with the ones the fixture expects. A line that must give a
# diagnostic ends with `// expect: <rule>`, with the rule repeated once for each diagnostic. A
# line without that comment must give none of the rules. Diagnostics of other rules are not part
# of the contract and are ignored. Nothing is written into the tracked files: the pinned tool is
# unpacked into .build/tools, and the fixtures are linted in a scratch folder that is removed at
# the end.
#
# Where a fixture is linted depends on where it lies in Fixtures/Lint. A file directly in that
# folder is linted as a file of LIBRARY_DIR, so a repository whose fixtures are all in one flat
# folder works as it did before subfolders were read, without a change. A file in a subfolder is
# linted in the same subfolder of LIBRARY_DIR, so that a rule meant for one folder, such as Domain,
# is proved there, and a fixture in the root proves that the rule does not reach the root. A file
# under Outside is linted at the same path counted from the root of the scratch copy, outside the
# library: no rule of the contract applies there, so such a fixture expects nothing, and a
# diagnostic in it fails the check. That is how a rule that is too wide is caught, one that reaches
# a fixture package or a second module.
#
# Exit codes: 0 every rule fires where expected and nowhere else, 1 a line differs, 2 the check
# could not be made. A tool that fails by itself, such as the fetch of SwiftLint or python3, can
# end the script with its own status.

set -euo pipefail

# ==== Settings of this repository =======================================================
# This block is the only part of the script that is specific to this repository. The body
# below the end marker names nothing of it, so a repository with another layout changes only
# these settings.

# The folder of the package layout that the include patterns of the rules name, relative to the
# repository root. The fixtures are linted as files of this folder, or of its subfolders.
LIBRARY_DIR="Sources/DMAction"
# The rules of the contract, separated by spaces. Each one needs a fixture that expects it.
RULES="domain_foundation_only domain_imports domain_no_facade_types force_unwrapping no_process_termination"
# The folder of the fixtures, relative to the repository root.
FIXTURE_DIR="Fixtures/Lint"

# ==== End of the settings ===============================================================

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=SCRIPTDIR/swiftlint-tool.sh
. "$ROOT/Scripts/swiftlint-tool.sh"

fail() {  # <status> <message>
    echo "check-lint-contract: $2" >&2
    exit "$1"
}

# The include patterns of the rules name this folder. Without it they lint nothing real, while the
# fixtures, which the script puts there itself, would still pass.
if [ ! -d "$ROOT/$LIBRARY_DIR" ]; then
    fail 2 "$LIBRARY_DIR does not exist, and the include patterns of the rules name it"
fi

VERSION="$(swiftlint_version "$ROOT" check-lint-contract)"
SWIFTLINT="$(swiftlint_fetch "$ROOT" "$VERSION" check-lint-contract)"

FIXTURES=()
while IFS= read -r FIXTURE; do
    FIXTURES+=("$FIXTURE")
done < <(find "$ROOT/$FIXTURE_DIR" -type f -name '*.txt' 2> /dev/null | LC_ALL=C sort)
if [ "${#FIXTURES[@]}" -eq 0 ]; then
    fail 2 "no fixture found in $FIXTURE_DIR"
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-lint-contract.XXXXXX")"
# shellcheck disable=SC2329  # invoked by the trap below
cleanup() {  # The EXIT trap below calls it. skipcq: SH-2329
    rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$WORK/$LIBRARY_DIR"
cp "$ROOT/.swiftlint.yml" "$WORK/.swiftlint.yml"
# One row for each fixture: its path in the fixture folder, its copy in the scratch folder, and
# whether it lies inside the library.
: > "$WORK/fixtures.tsv"
for FIXTURE in "${FIXTURES[@]}"; do
    RELATIVE="${FIXTURE#"$ROOT/$FIXTURE_DIR/"}"
    case "$RELATIVE" in
        Outside/*)
            KIND="outside"
            COPY="$WORK/${RELATIVE#Outside/}"
            case "$COPY" in
                "$WORK/$LIBRARY_DIR"/*)
                    fail 2 "$FIXTURE_DIR/$RELATIVE would be linted inside $LIBRARY_DIR, and a fixture under Outside must lie outside it"
                    ;;
            esac
            ;;
        *)
            KIND="library"
            COPY="$WORK/$LIBRARY_DIR/$RELATIVE"
            ;;
    esac
    COPY="${COPY%.txt}.swift"
    mkdir -p "$(dirname "$COPY")"
    cp "$FIXTURE" "$COPY"
    printf '%s\t%s\t%s\n' "$RELATIVE" "$COPY" "$KIND" >> "$WORK/fixtures.tsv"
done

# Exit 0 is a clean run and 2 is a run that found serious violations; both have a report. Any
# other status means that SwiftLint itself failed.
STATUS=0
(cd "$WORK" && "$SWIFTLINT" lint --no-cache --reporter json > report.json 2> report.log) || STATUS=$?
if [ "$STATUS" -ne 0 ] && [ "$STATUS" -ne 2 ]; then
    cat "$WORK/report.log" >&2
    fail 2 "SwiftLint failed with status $STATUS"
fi
# A run that lints no file reports no violation, and every rule would look quiet.
LINTED="$(LC_ALL=C sed -n 's/^Done linting!.* in \([0-9][0-9]*\) files*\.$/\1/p' "$WORK/report.log")"
if [ -z "$LINTED" ] || [ "$LINTED" -ne "${#FIXTURES[@]}" ]; then
    cat "$WORK/report.log" >&2
    fail 2 "SwiftLint linted ${LINTED:-no} files, and there are ${#FIXTURES[@]} fixtures"
fi

python3 - "$WORK/report.json" "$RULES" "$ROOT/$FIXTURE_DIR" "$WORK/fixtures.tsv" <<'PY'
import collections
import json
import os
import re
import sys

report_path, rules_text, fixture_dir, map_path = sys.argv[1:5]
rules = rules_text.split()


def stop(message):
    print(f"check-lint-contract: {message}", file=sys.stderr)
    sys.exit(2)


# (path in the fixture folder, path of the fixture, real path of its scratch copy, outside the library)
fixtures = []
for row in open(map_path, encoding="utf-8").read().splitlines():
    relative, copy, kind = row.split("\t")
    fixtures.append((relative, os.path.join(fixture_dir, relative), os.path.realpath(copy), kind == "outside"))

expected = {}
expecting = set()
for relative, path, _, outside in fixtures:
    for number, line in enumerate(open(path, encoding="utf-8").read().split("\n"), 1):
        match = re.search(r"//\s*expect:\s*([A-Za-z_][A-Za-z_ ]*?)\s*$", line)
        if not match:
            continue
        if outside:
            stop(f"{relative}:{number} expects a diagnostic, and a fixture under Outside expects none: no rule applies outside the library")
        wanted = match.group(1).split()
        for rule in wanted:
            if rule not in rules:
                stop(f"{relative}:{number} expects '{rule}', which is not a rule of the contract ({' '.join(rules)})")
        expected[(relative, number)] = sorted(wanted)
        expecting.update(wanted)
for rule in rules:
    if rule not in expecting:
        stop(f"no fixture expects the rule '{rule}', so nothing proves that it fires")

try:
    report = json.load(open(report_path, encoding="utf-8"))
except ValueError as error:
    stop(f"the report of SwiftLint is not JSON: {error}")

# The scratch folder lies under /var on macOS, which is a link to /private/var: real paths on both sides.
copies = {copy: relative for relative, _, copy, _ in fixtures}
actual = collections.defaultdict(list)
for violation in report:
    if violation["rule_id"] in rules:
        relative = copies.get(os.path.realpath(violation["file"]))
        if relative is None:
            stop(f"SwiftLint reported {violation['rule_id']} in {violation['file']}, which is no fixture")
        actual[(relative, violation["line"])].append(violation["rule_id"])

problems = []
for key in sorted(set(expected) | set(actual)):
    wanted, got = expected.get(key, []), sorted(actual.get(key, []))
    if wanted != got:
        problems.append(f"  {key[0]}:{key[1]}: expected {' '.join(wanted) or 'no diagnostic'}, got {' '.join(got) or 'no diagnostic'}")
if problems:
    print("check-lint-contract: the lint rules do not do what the fixtures expect:", file=sys.stderr)
    print("\n".join(problems), file=sys.stderr)
    sys.exit(1)
print(f"check-lint-contract: the {len(rules)} rules fire on {len(expected)} expected lines of {len(fixtures)} fixtures and on no other line.")
PY

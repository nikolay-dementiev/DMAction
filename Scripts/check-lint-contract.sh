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
for FIXTURE in "$ROOT/$FIXTURE_DIR"/*.txt; do
    if [ -f "$FIXTURE" ]; then
        FIXTURES+=("$FIXTURE")
    fi
done
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
for FIXTURE in "${FIXTURES[@]}"; do
    cp "$FIXTURE" "$WORK/$LIBRARY_DIR/$(basename "$FIXTURE" .txt).swift"
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

python3 - "$WORK/report.json" "$RULES" "${FIXTURES[@]}" <<'PY'
import collections
import json
import os
import re
import sys

report_path, rules_text = sys.argv[1:3]
fixtures = sys.argv[3:]
rules = rules_text.split()


def stop(message):
    print(f"check-lint-contract: {message}", file=sys.stderr)
    sys.exit(2)


expected = {}
expecting = set()
for path in fixtures:
    name = os.path.basename(path)
    for number, line in enumerate(open(path, encoding="utf-8").read().split("\n"), 1):
        match = re.search(r"//\s*expect:\s*([A-Za-z_][A-Za-z_ ]*?)\s*$", line)
        if not match:
            continue
        wanted = match.group(1).split()
        for rule in wanted:
            if rule not in rules:
                stop(f"{name}:{number} expects '{rule}', which is not a rule of the contract ({' '.join(rules)})")
        expected[(name, number)] = sorted(wanted)
        expecting.update(wanted)
for rule in rules:
    if rule not in expecting:
        stop(f"no fixture expects the rule '{rule}', so nothing proves that it fires")

try:
    report = json.load(open(report_path, encoding="utf-8"))
except ValueError as error:
    stop(f"the report of SwiftLint is not JSON: {error}")

actual = collections.defaultdict(list)
for violation in report:
    if violation["rule_id"] in rules:
        name = os.path.basename(violation["file"])[: -len(".swift")] + ".txt"
        actual[(name, violation["line"])].append(violation["rule_id"])

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

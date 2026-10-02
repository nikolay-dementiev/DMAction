#!/bin/bash
#
# Fails when the line coverage of the library target is below the floor.
#
#   Scripts/coverage-gate.sh <result bundle> [floor in percent]
#
# The bundle is one that xcodebuild recorded with -enableCodeCoverage YES. The numbers come
# from xccov. The floor is a lower bound, not a goal: a test that cannot fail raises the
# number and proves nothing.

set -euo pipefail

BUNDLE="${1:?give the path of an .xcresult bundle recorded with code coverage}"
FLOOR="${2:-90}"
TARGET="DMAction"
REPORT="$(mktemp -t coverage-gate)"
trap 'rm -f "$REPORT"' EXIT

xcrun xccov view --report --json "$BUNDLE" > "$REPORT"

python3 - "$REPORT" "$TARGET" "$FLOOR" <<'PY'
import json
import sys

report = json.load(open(sys.argv[1]))
target_name, floor = sys.argv[2], float(sys.argv[3])
target = next((t for t in report.get("targets", []) if t.get("name") == target_name), None)
if target is None:
    print(f"coverage-gate: no target named {target_name} in the bundle", file=sys.stderr)
    sys.exit(2)
for source in sorted(target.get("files", []), key=lambda entry: entry["name"]):
    percent = source["lineCoverage"] * 100
    lines = "{}/{}".format(source["coveredLines"], source["executableLines"])
    print(f"  {percent:6.2f} %  {lines:>9}  {source['name']}")
percent = target["lineCoverage"] * 100
lines = "{}/{}".format(target["coveredLines"], target["executableLines"])
print(f"coverage-gate: {target_name} {percent:.2f} % of lines ({lines}), floor {floor:g} %")
sys.exit(0 if percent >= floor else 1)
PY

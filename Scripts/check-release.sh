#!/bin/bash
#
# Checks that a release version, the podspec and the changelog agree.
#
#   Scripts/check-release.sh <version>           check; exit 1 on any mismatch
#   Scripts/check-release.sh --notes <version>   print the changelog section of that version
#
# A release starts from a tag that is the version itself, such as 1.1.0. The podspec must name
# the same version, and the newest heading of CHANGELOG.md must be `## [1.1.0] - YYYY-MM-DD`,
# with the date of the release. The release notes are the section under that heading. The
# release workflow runs this script on the tag; run it before you push one.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHANGELOG="$ROOT/CHANGELOG.md"
PODSPEC="$ROOT/DMAction.podspec"

NOTES=0
if [ "${1:-}" = "--notes" ]; then
    NOTES=1
    shift
fi
VERSION="${1:-}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "usage: Scripts/check-release.sh [--notes] <version>, a version such as 1.1.0" >&2
    exit 2
fi

if [ "$NOTES" -eq 1 ]; then
    # The lines between the version's heading and the next release heading, without the blank
    # lines at either end.
    awk -v heading="## [$VERSION]" '
        index($0, heading) == 1 { inside = 1; next }
        inside && /^## \[/ { exit }
        inside { lines[++count] = $0 }
        END {
            first = 1; while (first <= count && lines[first] == "") first++
            last = count; while (last >= first && lines[last] == "") last--
            for (line = first; line <= last; line++) print lines[line]
        }
    ' "$CHANGELOG"
    exit 0
fi

PROBLEMS=()

PODSPEC_VERSION="$(sed -n "s/^ *s\.version *= *'\([^']*\)'.*/\1/p" "$PODSPEC")"
if [ "$PODSPEC_VERSION" != "$VERSION" ]; then
    PROBLEMS+=("the podspec names version '$PODSPEC_VERSION', not $VERSION")
fi

NEWEST="$(grep -m 1 -E '^## \[' "$CHANGELOG" || true)"
if [[ "$NEWEST" =~ ^##\ \[([^]]+)\]\ -\ (.*)$ ]]; then
    HEADING_VERSION="${BASH_REMATCH[1]}"
    HEADING_DATE="${BASH_REMATCH[2]}"
    if [ "$HEADING_VERSION" != "$VERSION" ]; then
        PROBLEMS+=("the newest changelog heading is for $HEADING_VERSION, not $VERSION")
    elif ! [[ "$HEADING_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        PROBLEMS+=("the changelog heading of $VERSION has '$HEADING_DATE' where the release date belongs")
    fi
else
    PROBLEMS+=("CHANGELOG.md has no heading of the form '## [version] - date'")
fi

if [ "${#PROBLEMS[@]}" -gt 0 ]; then
    echo "check-release: $VERSION is not ready to release:" >&2
    printf '  - %s\n' "${PROBLEMS[@]}" >&2
    exit 1
fi
echo "check-release: the podspec and the changelog agree on $VERSION, released $HEADING_DATE."

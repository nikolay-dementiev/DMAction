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

# The checks of this script are case patterns, because a regular-expression match is undefined
# in POSIX sh. A version is three groups of digits joined by dots, such as 1.1.0: nothing but
# digits and dots, no leading, trailing or doubled dot, and exactly two dots.
valid_version() {
    case "$1" in
        '' | .* | *. | *..* | *[!0123456789.]* | *.*.*.*) return 1 ;;
        *.*.*) return 0 ;;
    esac
    return 1
}

if ! valid_version "$VERSION"; then
    echo "usage: Scripts/check-release.sh [--notes] <version>, a version such as 1.1.0" >&2
    exit 2
fi

# The lines between the version's heading and the next release heading, without the blank lines
# at either end. Empty when the version has no heading or nothing under it.
notes() {
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
}

if [ "$NOTES" -eq 1 ]; then
    TEXT="$(notes)"
    if [ -z "$TEXT" ]; then
        echo "check-release: CHANGELOG.md has no notes under a heading for $VERSION" >&2
        exit 1
    fi
    printf '%s\n' "$TEXT"
    exit 0
fi

PROBLEMS=()

if [ -z "$(notes)" ]; then
    PROBLEMS+=("CHANGELOG.md has no notes under a heading for $VERSION")
fi

PODSPEC_VERSION="$(sed -n "s/^ *s\.version *= *'\([^']*\)'.*/\1/p" "$PODSPEC")"
if [ "$PODSPEC_VERSION" != "$VERSION" ]; then
    PROBLEMS+=("the podspec names version '$PODSPEC_VERSION', not $VERSION")
fi

# A release date is four digits, a dash, two digits, a dash and two digits, such as 2026-10-03.
# Whether that day exists is asked of python3 below.
valid_date_form() {
    case "$1" in
        [0123456789][0123456789][0123456789][0123456789]-[0123456789][0123456789]-[0123456789][0123456789]) return 0 ;;
    esac
    return 1
}

# The version and the date of the newest release heading, '## [version] - date'. sed prints them
# only when the whole heading has that form, and it reads the heading as bytes, so that no locale
# stops it on a character of the heading. A heading with an empty version does not have the form.
NEWEST="$(grep -m 1 -E '^## \[' "$CHANGELOG" || true)"
HEADING_VERSION="$(printf '%s\n' "$NEWEST" | LC_ALL=C sed -n 's/^## \[\([^]]*\)\] - \(.*\)$/\1/p')"
HEADING_DATE="$(printf '%s\n' "$NEWEST" | LC_ALL=C sed -n 's/^## \[\([^]]*\)\] - \(.*\)$/\2/p')"
if [ -n "$HEADING_VERSION" ]; then
    if [ "$HEADING_VERSION" != "$VERSION" ]; then
        PROBLEMS+=("the newest changelog heading is for $HEADING_VERSION, not $VERSION")
    elif ! valid_date_form "$HEADING_DATE"; then
        PROBLEMS+=("the changelog heading of $VERSION has '$HEADING_DATE' where the release date belongs")
    elif ! python3 -c 'import datetime, sys; datetime.date.fromisoformat(sys.argv[1])' "$HEADING_DATE" 2> /dev/null; then
        PROBLEMS+=("the changelog heading of $VERSION has '$HEADING_DATE', which is not a day of the calendar")
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

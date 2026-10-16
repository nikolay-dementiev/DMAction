#!/bin/bash
#
# Checks a release version against the changelog, and that the podspec names the frozen version.
#
#   Scripts/check-release.sh <version>           check; exit 1 if not ready, 2 if it cannot compare
#   Scripts/check-release.sh --notes <version>   print the changelog section of that version
#
# A release starts from a tag that is the version itself, such as 1.1.0. The newest heading of
# CHANGELOG.md must be `## [1.1.0] - YYYY-MM-DD`, with the date of the release. The release notes
# are the section under that heading. The pod is frozen: the podspec stays at the last version
# published to the trunk, FROZEN_POD_VERSION below, whatever the release version is. The release
# workflow runs this script on the tag; run it before you push one.
#
# The release is also compared with the one before it, the heading below the newest. It must raise
# the major version when the baseline lost or changed a line since the tag of that release
# (Scripts/check-api.sh --since), or when its notes have a `### Breaking changes` subsection, where
# a change of behaviour is declared because no script can see one. Lines that were only added pass
# with a reminder to review them. The first release has none before it and is not compared, and
# neither is a release that holds no baseline; the script says so. A tag that is not in the
# repository, or a comparison that cannot run, is exit 2, never a pass. Run Scripts/check-api.sh
# first: the baseline is the interface of the library only while that check passes. The heading of
# the subsection is matched in any letter case.
#
# Exit codes: 0 ready, 1 not ready, 2 wrong usage or the comparison could not run.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHANGELOG="$ROOT/CHANGELOG.md"
PODSPEC="$ROOT/DMAction.podspec"
# The CocoaPods channel ended with 1.1.0 (README, "CocoaPods"). The podspec stays at that
# version; the release version is checked against the changelog alone.
FROZEN_POD_VERSION="1.1.0"

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
if [ "$PODSPEC_VERSION" != "$FROZEN_POD_VERSION" ]; then
    PROBLEMS+=("the podspec names version '$PODSPEC_VERSION'; the pod is frozen at $FROZEN_POD_VERSION")
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

# The release before this one is the version of the second release heading. It has no meaning when
# the newest heading is for another version, which is a problem already.
COULD_NOT_COMPARE=0
if [ "$HEADING_VERSION" = "$VERSION" ]; then
    PREVIOUS_HEADING="$(LC_ALL=C awk '/^## \[/ { count++ } count == 2 { print; exit }' "$CHANGELOG")"
    if [ -z "$PREVIOUS_HEADING" ]; then
        echo "check-release: CHANGELOG.md has no release below $VERSION, so the interface was not compared."
    else
        PREVIOUS="$(printf '%s\n' "$PREVIOUS_HEADING" | LC_ALL=C sed -n 's/^## \[\([^]]*\)\].*$/\1/p')"
        if ! valid_version "$PREVIOUS"; then
            PROBLEMS+=("the changelog heading below $VERSION is not a release version: '$PREVIOUS_HEADING'")
        else
            RAISES_MAJOR=0
            if [ "${VERSION%%.*}" -gt "${PREVIOUS%%.*}" ]; then
                RAISES_MAJOR=1
            fi
            BREAKING="$(notes | grep -c -i -E '^### Breaking changes[[:space:]]*$' || true)"
            if [ "$BREAKING" -gt 0 ] && [ "$RAISES_MAJOR" -eq 0 ]; then
                PROBLEMS+=("the notes of $VERSION have a '### Breaking changes' subsection: that needs a new major version, and $VERSION does not raise the major version of $PREVIOUS")
            fi
            if ! git -C "$ROOT" rev-parse --verify --quiet "refs/tags/$PREVIOUS^{commit}" > /dev/null; then
                PROBLEMS+=("the tag $PREVIOUS of the release below $VERSION is not in this repository, so the interface cannot be compared: git fetch --tags")
                COULD_NOT_COMPARE=1
            else
                DELTA_STATUS=0
                DELTA="$("$ROOT/Scripts/check-api.sh" --since "$PREVIOUS" 2>&1)" || DELTA_STATUS=$?
                case "$DELTA_STATUS" in
                    0) ;;
                    1)
                        # A script that stops on an error exits with 1 as well, so the exit code
                        # counts only with the heading of the lines that were removed or changed.
                        case "$DELTA" in
                            *"Removed or changed"*)
                                if [ "$RAISES_MAJOR" -eq 0 ]; then
                                    PROBLEMS+=("the interface lost or changed lines since $PREVIOUS (Scripts/check-api.sh --since $PREVIOUS lists them): that needs a new major version, and $VERSION does not raise the major version of $PREVIOUS")
                                fi
                                ;;
                            *)
                                PROBLEMS+=("the interface could not be compared with $PREVIOUS: $(printf '%s\n' "$DELTA" | sed -n '1p')")
                                COULD_NOT_COMPARE=1
                                ;;
                        esac
                        ;;
                    3)
                        echo "check-release: lines were added to the interface since $PREVIOUS. Review that none adds a protocol requirement or an overload that makes a call ambiguous: either needs a new major version."
                        ;;
                    4)
                        echo "check-release: the interface was not compared with $PREVIOUS: that release holds no baseline."
                        ;;
                    *)
                        PROBLEMS+=("the interface could not be compared with $PREVIOUS: $(printf '%s\n' "$DELTA" | sed -n '1p')")
                        COULD_NOT_COMPARE=1
                        ;;
                esac
            fi
        fi
    fi
fi

if [ "${#PROBLEMS[@]}" -gt 0 ]; then
    echo "check-release: $VERSION is not ready to release:" >&2
    printf '  - %s\n' "${PROBLEMS[@]}" >&2
    if [ "$COULD_NOT_COMPARE" -eq 1 ]; then
        exit 2
    fi
    exit 1
fi
echo "check-release: the changelog agrees on $VERSION, released $HEADING_DATE; the pod stays at $FROZEN_POD_VERSION."

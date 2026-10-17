# shellcheck shell=bash
#
# Finds the SwiftLint that .swiftlint.yml pins. Scripts/lint.sh and Scripts/check-lint-contract.sh
# source this file; it is not run on its own.
#
#   swiftlint_version <repository root> <caller>            print the pinned version
#   swiftlint_fetch <repository root> <version> <caller>    print the path of the tool
#
# The tool is fetched once into .build/tools and checked against the pinned checksum before it is
# unpacked. Nothing is installed or upgraded on the machine. Runs at once on one checkout are
# safe: the archive and the tool each reach their final name with one rename. A problem goes to
# standard error with the name of the caller in front, and the function returns a status other
# than 0.

# SHA-256 of portable_swiftlint.zip of that release. It changes together with the version.
SWIFTLINT_CHECKSUM="c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0"

# The check is a case pattern, because a regular-expression match is undefined in POSIX sh. A
# version is three groups of digits joined by dots, such as 0.65.1: nothing but digits and dots,
# no leading, trailing or doubled dot, and exactly two dots.
valid_version() {
    case "$1" in
        '' | .* | *. | *..* | *[!0123456789.]* | *.*.*.*) return 1 ;;
        *.*.*) return 0 ;;
    esac
    return 1
}

swiftlint_version() {
    local root="$1" caller="$2" version
    version="$(sed -n 's/^swiftlint_version: *//p' "$root/.swiftlint.yml")" || return $?
    # The version goes into a path and a URL, so it must be a version and nothing else.
    if ! valid_version "$version"; then
        echo "$caller: .swiftlint.yml must pin swiftlint_version to a version such as 0.65.1, not '$version'" >&2
        return 2
    fi
    printf '%s\n' "$version"
}

swiftlint_fetch() {
    local root="$1" version="$2" caller="$3" tools archive actual part stage status
    tools="$root/.build/tools/swiftlint-$version"
    # The archive is checked on every run and the tool is taken out of it again, so a binary that
    # was put in its place is never run.
    mkdir -p "$tools" || return $?
    archive="$tools/portable_swiftlint.zip"
    if [ ! -f "$archive" ]; then
        # Fetched under a name of its own, so that an interrupted transfer never passes for the
        # archive and two runs that fetch at once never share a file.
        part="$(mktemp "$archive.XXXXXX")" || return $?
        status=0
        curl --fail --silent --show-error --location --retry 3 --proto '=https' --proto-redir '=https' \
            "https://github.com/realm/SwiftLint/releases/download/$version/portable_swiftlint.zip" \
            --output "$part" || status=$?
        if [ "$status" -eq 0 ]; then
            mv "$part" "$archive" || status=$?
        fi
        if [ "$status" -ne 0 ]; then
            rm -f "$part"
            return "$status"
        fi
    fi
    actual="$(shasum -a 256 "$archive" | cut -d ' ' -f 1)" || return $?
    if [ "$actual" != "$SWIFTLINT_CHECKSUM" ]; then
        # A wrong archive must not block every later run: the next one fetches it again.
        rm -f "$archive" || return $?
        echo "$caller: the SwiftLint $version archive had checksum $actual, expected $SWIFTLINT_CHECKSUM. It was removed." >&2
        return 2
    fi
    # Unpacked into a folder of its own and moved onto its place with one rename. A run that is
    # executing the tool keeps its file, and a run that starts now gets a whole one, even when
    # another run unpacks at the same moment. A run that is killed in the middle leaves its folder
    # in .build/tools, which a clean of .build removes.
    stage="$(mktemp -d "$tools/unpack.XXXXXX")" || return $?
    status=0
    unzip -q -o "$archive" swiftlint -d "$stage" || status=$?
    if [ "$status" -eq 0 ]; then
        mv -f "$stage/swiftlint" "$tools/swiftlint" || status=$?
    fi
    rm -f "$stage/swiftlint"
    rmdir "$stage" || echo "$caller: could not remove $stage" >&2
    [ "$status" -eq 0 ] || return "$status"
    printf '%s\n' "$tools/swiftlint"
}

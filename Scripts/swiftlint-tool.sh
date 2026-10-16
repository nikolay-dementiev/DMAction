# shellcheck shell=bash
#
# Finds the SwiftLint that .swiftlint.yml pins. Scripts/lint.sh and Scripts/check-lint-contract.sh
# source this file; it is not run on its own.
#
#   swiftlint_version <repository root> <caller>            print the pinned version
#   swiftlint_fetch <repository root> <version> <caller>    print the path of the tool
#
# The tool is fetched once into .build/tools and checked against the pinned checksum before it is
# unpacked. Nothing is installed or upgraded on the machine. A problem goes to standard error
# with the name of the caller in front, and the function returns a status other than 0.

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
    local root="$1" version="$2" caller="$3" tools archive actual
    tools="$root/.build/tools/swiftlint-$version"
    # The archive is checked on every run and the tool is taken out of it again, so a binary that
    # was put in its place is never run.
    mkdir -p "$tools" || return $?
    archive="$tools/portable_swiftlint.zip"
    if [ ! -f "$archive" ]; then
        # Fetched under another name, so an interrupted transfer never passes for the archive.
        curl --fail --silent --show-error --location --retry 3 --proto '=https' --proto-redir '=https' \
            "https://github.com/realm/SwiftLint/releases/download/$version/portable_swiftlint.zip" \
            --output "$archive.part" || return $?
        mv "$archive.part" "$archive" || return $?
    fi
    actual="$(shasum -a 256 "$archive" | cut -d ' ' -f 1)" || return $?
    if [ "$actual" != "$SWIFTLINT_CHECKSUM" ]; then
        # A wrong archive must not block every later run: the next one fetches it again.
        rm -f "$archive" || return $?
        echo "$caller: the SwiftLint $version archive had checksum $actual, expected $SWIFTLINT_CHECKSUM. It was removed." >&2
        return 2
    fi
    unzip -q -o "$archive" swiftlint -d "$tools" || return $?
    printf '%s\n' "$tools/swiftlint"
}

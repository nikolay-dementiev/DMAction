#!/bin/bash
#
# Compares the public API of the library with a git ref using swift-api-digester, which loads the
# compiled modules. It classifies what the text comparison of Scripts/check-api.sh shows only as an
# added line: a protocol requirement added without a default, a method that an extension declares
# and that becomes a requirement, a narrowed generic requirement.
#
#   Scripts/check-api-digester.sh <ref>          compare the working tree with the git ref
#   Scripts/check-api-digester.sh --self-test    run the mapping below on a scratch package
#
# swift package diagnose-api-breaking-changes ends with status 1 both for a break and for every
# failure (an unknown ref, a wrong product, a baseline that does not build), so the status alone
# cannot tell them apart. The verdict is printed on standard output, so this script reads the
# status and the text together: a pass is status 0 and a "No breaking changes detected" line, a
# break is status 1 and a "breaking change(s) detected" line, and anything else is a failure.
#
# Exit codes: 0 no break, 1 a break, which is printed, 2 the comparison could not be made.
#
# It builds the ref and the working tree for the host, so a declaration behind #if os(iOS) is not
# compared. It does not see a changed default value, an added associated type with a default, or
# the resolution of an overload. A green result is evidence, not proof. Apart from .build, the only
# thing it writes is a scratch folder that it removes at the end.

set -euo pipefail

# ==== Settings of this repository =======================================================
# This block is the only part of the script that is specific to this repository. The body
# below the end marker names nothing of it.

# The library product whose modules are compared.
PRODUCT="DMAction"

# ==== End of the settings ===============================================================

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

stop() {  # <message>: the comparison could not be made
    echo "check-api-digester: $1" >&2
    exit 2
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-api-digester.XXXXXX")"
# shellcheck disable=SC2329  # invoked by the trap below
cleanup() {  # The EXIT trap below calls it. skipcq: SH-2329
    rm -rf "$WORK"
}
trap cleanup EXIT

# Reads the status and the text of the digester together and exits 0, 1 or 2.
map_result() {  # <ref> <status>
    local ref="$1" status="$2" pass_line break_line
    pass_line="$(grep -E '^No breaking changes detected in ' "$WORK/out" | head -1 || true)"
    break_line="$(grep -E '^[0-9]+ breaking changes? detected in ' "$WORK/out" | head -1 || true)"
    if [ "$status" -eq 0 ] && [ -n "$pass_line" ] && [ -z "$break_line" ]; then
        echo "check-api-digester: no break since $ref: $pass_line"
        exit 0
    fi
    if [ "$status" -eq 1 ] && [ -n "$break_line" ] && [ -z "$pass_line" ]; then
        echo "check-api-digester: ${break_line%:} since $ref"
        { grep -v -F "$break_line" "$WORK/out" | grep -v -E '^[[:space:]]*$' | sed 's/^/  /'; } || true
        exit 1
    fi
    echo "check-api-digester: could not compare with $ref (status $status):" >&2
    # The progress of the build and the SwiftPM warning about the docc catalog of the baseline
    # checkout (two lines) are not the reason.
    {
        grep -v -E '^\[[0-9]+/[0-9]+\]|^Building for |^Build complete|^Write |found [0-9]+ file\(s\) which are unhandled|/apidiff/[0-9a-f]+-checkout/' "$WORK/err" || true
        head -5 "$WORK/out"
    } | head -20 | sed 's/^/  /' >&2
    exit 2
}

compare() {  # <ref>
    local ref="$1" status=0
    command -v swift > /dev/null || stop "swift is not installed"
    git -C "$ROOT" rev-parse --git-dir > /dev/null 2>&1 || stop "$ROOT is not a git repository, and the baseline is a ref of it"
    (cd "$ROOT" && swift package diagnose-api-breaking-changes "$ref" --products "$PRODUCT") \
        > "$WORK/out" 2> "$WORK/err" || status=$?
    map_result "$ref" "$status"
}

# The Swift source of the scratch package, by variant.
probe_source() {  # <baseline|removed|requirement|added|broken>
    case "$1" in
        baseline | broken)
            cat <<'SWIFT'
public protocol Greeter {
    func greet() -> String
}

public struct Greeting: Greeter {
    public init() {}
    public func greet() -> String { "hi" }
    public func removed() -> Int { 1 }
}
SWIFT
            if [ "$1" = "broken" ]; then
                echo 'let brokenOnPurpose: Int = "not an int"'
            fi
            ;;
        removed)
            cat <<'SWIFT'
public protocol Greeter {
    func greet() -> String
}

public struct Greeting: Greeter {
    public init() {}
    public func greet() -> String { "hi" }
}
SWIFT
            ;;
        requirement)
            cat <<'SWIFT'
public protocol Greeter {
    func greet() -> String
    func shout() -> String
}

public struct Greeting: Greeter {
    public init() {}
    public func greet() -> String { "hi" }
    public func shout() -> String { "HI" }
    public func removed() -> Int { 1 }
}
SWIFT
            ;;
        added)
            cat <<'SWIFT'
public protocol Greeter {
    func greet() -> String
}

public struct Greeting: Greeter {
    public init() {}
    public func greet() -> String { "hi" }
    public func removed() -> Int { 1 }
    public func added() -> Int { 2 }
}
SWIFT
            ;;
    esac
}

# Runs the mapping on a scratch package with tagged commits, with no network. Each case changes
# the working tree, runs a copy of this script and compares the status and one line of its output.
self_test() {
    local scratch="$WORK/probe" shims="$WORK/shims" failures=0 total=0 wrapper
    wrapper="$scratch/Scripts/check-api-digester.sh"
    probe_git() {
        git -C "$scratch" -c user.name=probe -c user.email=probe@example.invalid \
            -c commit.gpgsign=false -c tag.gpgSign=false -c core.hooksPath=/dev/null "$@"
    }
    check() {  # <name> <expected status> <expected text> <command...>
        local name="$1" want="$2" text="$3" got=0 output
        shift 3
        total=$((total + 1))
        output="$("$@" 2>&1)" || got=$?
        if [ "$got" -eq "$want" ] && printf '%s\n' "$output" | grep -q -F -- "$text"; then
            echo "check-api-digester: ok   $name"
        else
            failures=$((failures + 1))
            echo "check-api-digester: FAIL $name: expected status $want and '$text', got status $got:" >&2
            printf '%s\n' "$output" | head -8 | sed 's/^/    /' >&2
        fi
    }

    mkdir -p "$scratch/Sources/Probe" "$scratch/Scripts" "$shims"
    cat > "$scratch/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Probe",
    products: [.library(name: "Probe", targets: ["Probe"])],
    targets: [.target(name: "Probe")],
    swiftLanguageModes: [.v6]
)
SWIFT
    probe_source baseline > "$scratch/Sources/Probe/Probe.swift"
    probe_git init -q || stop "the scratch package could not be set up"
    probe_git add -A || stop "the scratch package could not be committed"
    probe_git commit -q -m baseline || stop "the scratch package could not be committed"
    probe_git tag v1 || stop "the scratch package could not be committed"
    probe_source broken > "$scratch/Sources/Probe/Probe.swift"
    probe_git add -A || stop "the scratch package could not be committed"
    probe_git commit -q -m "a baseline that does not build" || stop "the scratch package could not be committed"
    probe_git tag broken || stop "the scratch package could not be committed"
    probe_git checkout -q v1 -- Sources || stop "the scratch package could not be restored"
    sed 's/^PRODUCT=".*"$/PRODUCT="Probe"/' "$SCRIPT" > "$wrapper"
    chmod 755 "$wrapper"

    # The result of the digester on real changes.
    probe_source removed > "$scratch/Sources/Probe/Probe.swift"
    check "a removed public member is a break" 1 "removed()" "$wrapper" v1
    probe_source requirement > "$scratch/Sources/Probe/Probe.swift"
    check "a protocol requirement added without a default is a break" 1 "added as a protocol requirement" "$wrapper" v1
    probe_source added > "$scratch/Sources/Probe/Probe.swift"
    check "an added public member is not a break" 0 "no break since v1" "$wrapper" v1
    probe_git checkout -q v1 -- Sources
    check "an unknown ref is a failure" 2 "could not compare with no-such-ref" "$wrapper" no-such-ref
    check "a baseline that does not build is a failure" 2 "could not compare with broken" "$wrapper" broken
    sed 's/^PRODUCT=".*"$/PRODUCT="Nope"/' "$SCRIPT" > "$wrapper"
    check "a wrong product is a failure" 2 "no such product" "$wrapper" v1
    sed 's/^PRODUCT=".*"$/PRODUCT="Probe"/' "$SCRIPT" > "$wrapper"

    # The mapping alone, with a swift that says what it is told to.
    cat > "$shims/swift" <<'SHIM'
#!/bin/bash
case "$SHIM_MODE" in
    pass-status-0) echo "No breaking changes detected in Probe"; exit 0 ;;
    break-status-1) echo "1 breaking change detected in Probe:"; echo "  API breakage: x"; exit 1 ;;
    pass-status-1) echo "No breaking changes detected in Probe"; exit 1 ;;
    break-status-0) echo "1 breaking change detected in Probe:"; echo "  API breakage: x"; exit 0 ;;
    empty-status-0) exit 0 ;;
    empty-status-1) exit 1 ;;
esac
SHIM
    chmod 755 "$shims/swift"
    check "status 0 and the pass line is a pass" 0 "no break since v1" env PATH="$shims:$PATH" SHIM_MODE=pass-status-0 "$wrapper" v1
    check "status 1 and the break header is a break" 1 "1 breaking change detected in Probe since v1" env PATH="$shims:$PATH" SHIM_MODE=break-status-1 "$wrapper" v1
    check "status 1 with the pass line is a failure" 2 "could not compare with v1" env PATH="$shims:$PATH" SHIM_MODE=pass-status-1 "$wrapper" v1
    check "status 0 with the break header is a failure" 2 "could not compare with v1" env PATH="$shims:$PATH" SHIM_MODE=break-status-0 "$wrapper" v1
    check "status 0 with no text is a failure" 2 "could not compare with v1" env PATH="$shims:$PATH" SHIM_MODE=empty-status-0 "$wrapper" v1
    check "status 1 with no text is a failure" 2 "could not compare with v1" env PATH="$shims:$PATH" SHIM_MODE=empty-status-1 "$wrapper" v1

    if [ "$failures" -gt 0 ]; then
        echo "check-api-digester: $failures of $total self-test cases failed" >&2
        exit 1
    fi
    echo "check-api-digester: self-test: $total cases, all ok."
}

usage() {
    echo "usage: Scripts/check-api-digester.sh <ref> | --self-test" >&2
    exit 2
}

case "${1:-}" in
    --self-test)
        [ "$#" -eq 1 ] || usage
        self_test
        ;;
    '' | -*) usage ;;
    *)
        [ "$#" -eq 1 ] || usage
        compare "$1"
        ;;
esac

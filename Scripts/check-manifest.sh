#!/bin/bash
#
# Checks what a consumer of the package gets, and what the repository's own tooling does
# on the machine of whoever runs it.
#
#   Scripts/check-manifest.sh
#
# 1. The manifest has no dependency by branch or revision, uses no plugin on any target
#    and does not read the environment. SwiftPM refuses a version requirement on a package
#    that has an unstable dependency, a build plugin of a dependency runs in every
#    consumer's build, and a manifest that reads the environment describes more than one
#    package.
# 2. A consumer that asks for the package by version resolves it. This runs against a
#    throw-away tagged copy of the tracked manifest and sources: a consumer that depends
#    on the checkout by path cannot show that failure.
# 3. Fixtures/Consumer builds without a warning. It uses the released public declarations
#    with their exact types and the shapes the downstream package relies on, so if it
#    stops building, a consumer's code stops building.
# 4. No tracked file under Examples/ deletes a directory tree. The example's Pod helper
#    used to delete the Xcode DerivedData folder of the whole machine on every install.
#    This is a text search: it catches the usual spellings of such a call, it does not
#    prove that a script has no side effect.
# 5. The podspec describes the same product as the manifest: the same platforms, the
#    language mode the package is built in, and no link against a test framework.
# 6. The uses across isolation domains that the Swift 6 compiler rejects today are still
#    rejected, each with the error it names. Each one is a target of Fixtures/Rejected.
#    One that starts to compile means the concurrency limits of the library have changed.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="DMAction"
WORK="$ROOT/.build/check-manifest"
FAILED=0

mkdir -p "$WORK"
cd "$ROOT"

# The folders this run creates with mktemp inside $WORK. They hold a copy of the
# tracked sources and build output, and they leave with the run. The logs stay.
PROBE=""
DERIVED=""
REJECTED_BUILD=""
# shellcheck disable=SC2329  # invoked by the trap below
cleanup() {
    if [ -n "$PROBE" ]; then rm -rf "$PROBE"; fi
    if [ -n "$DERIVED" ]; then rm -rf "$DERIVED"; fi
    if [ -n "$REJECTED_BUILD" ]; then rm -rf "$REJECTED_BUILD"; fi
}
trap cleanup EXIT

# 1. Static check of the manifest.
swift package --package-path "$ROOT" dump-package > "$WORK/manifest.json"
if ! python3 - "$WORK/manifest.json" "$ROOT/Package.swift" <<'PY'
import json
import re
import sys

manifest = json.load(open(sys.argv[1]))
source = open(sys.argv[2]).read()
problems = []
for dependency in manifest.get("dependencies", []):
    for entries in dependency.values():
        for entry in entries:
            requirement = entry.get("requirement", {})
            for unstable in ("branch", "revision"):
                if unstable in requirement:
                    problems.append(
                        f"dependency '{entry.get('identity')}' is required by {unstable} "
                        f"{requirement[unstable]}"
                    )
for target in manifest.get("targets", []):
    for usage in target.get("pluginUsages") or []:
        problems.append(f"target '{target['name']}' uses a plugin: {json.dumps(usage)}")
if re.search(r"ProcessInfo|getenv|\.environment\b", source):
    problems.append("Package.swift reads the environment")
for problem in problems:
    print(f"check-manifest: {problem}", file=sys.stderr)
sys.exit(1 if problems else 0)
PY
then
    FAILED=1
else
    echo "check-manifest: no unstable requirement, no plugin and no environment switch in Package.swift."
fi

# 2. Resolution by version, against a throw-away copy of the tracked files with a tag.
PROBE="$(mktemp -d "$WORK/version-probe.XXXXXX")"
mkdir -p "$PROBE/package" "$PROBE/consumer/Sources/Probe"
git ls-files -z -- Package.swift Sources | xargs -0 -I{} rsync -R {} "$PROBE/package/"
# The probe repository takes nothing from the git configuration of whoever runs this:
# no signing, no hooks, no identity.
probe_git() {
    git -C "$PROBE/package" \
        -c user.name=probe -c user.email=probe@example.invalid \
        -c commit.gpgsign=false -c tag.gpgSign=false -c core.hooksPath=/dev/null \
        "$@"
}
probe_git init -q
probe_git add -A
probe_git commit -q -m probe
probe_git tag 99.0.0
cat > "$PROBE/consumer/Package.swift" <<EOF
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Probe",
    platforms: [.iOS(.v17)],
    dependencies: [.package(url: "file://$PROBE/package", from: "99.0.0")],
    targets: [.target(name: "Probe", dependencies: [.product(name: "$MODULE", package: "package")])]
)
EOF
echo "import $MODULE" > "$PROBE/consumer/Sources/Probe/Probe.swift"
if swift package --package-path "$PROBE/consumer" resolve > "$WORK/version-resolution.log" 2>&1; then
    echo "check-manifest: a version requirement on the package resolves."
else
    echo "check-manifest: a version requirement on the package does not resolve:" >&2
    grep -E "error:|cannot be used|unstable" "$WORK/version-resolution.log" | cut -c1-300 | head -5 >&2 || true
    FAILED=1
fi

# 3. The consumer fixture. xcodebuild finds a package only in the current directory.
#    No flag skips the plugin validation: a consumer must not need one. A warning in the
#    fixture's own sources fails the check: a deprecation of a released symbol reaches a
#    consumer as a warning. Warnings cannot be made errors on the command line here,
#    because Xcode builds a package dependency with its warnings suppressed.
DERIVED="$(mktemp -d "$WORK/DerivedData.XXXXXX")"
cd "$ROOT/Fixtures/Consumer"
if ! xcodebuild build \
    -scheme Consumer \
    -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$DERIVED" \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
    > "$WORK/consumer-build.log" 2>&1; then
    echo "check-manifest: Fixtures/Consumer does not build. See ${WORK#"$ROOT"/}/consumer-build.log" >&2
    grep -E "error:" "$WORK/consumer-build.log" | sort -u | cut -c1-240 | head -20 >&2 || true
    FAILED=1
else
    WARNINGS="$(grep -F "/Fixtures/Consumer/" "$WORK/consumer-build.log" | grep -F ": warning: " | sort -u || true)"
    if [ -n "$WARNINGS" ]; then
        echo "check-manifest: Fixtures/Consumer builds with warnings, and so does a consumer's code:" >&2
        echo "$WARNINGS" | cut -c1-240 | head -20 >&2
        FAILED=1
    else
        echo "check-manifest: Fixtures/Consumer builds against this checkout without a warning."
    fi
fi
cd "$ROOT"

# 4. The example's tooling: a recursive rm with its flags in any order or as separate
#    arguments, the tree removals of Ruby and Python, find -delete, and any mention of the
#    machine-wide Xcode folders.
RECURSIVE_RM='(^|[^[:alnum:]_.-])rm[[:space:]]+(-[[:alnum:]-]+[[:space:]]+)*(-[a-zA-Z]*[rR]|--recursive)'
RM_AS_ARGUMENT='["'\'']rm["'\''][[:space:]]*,'
TREE_REMOVAL='FileUtils\.(rm_rf|rm_r|remove_dir|remove_entry)|rmtree|find[[:space:]].*[[:space:]]-delete'
MACHINE_FOLDER='DerivedData|Library/Developer'
DELETES="$(git grep -nE "$RECURSIVE_RM|$RM_AS_ARGUMENT|$TREE_REMOVAL|$MACHINE_FOLDER" \
    -- Examples ':(exclude,glob)**/.gitignore' || true)"
if [ -n "$DELETES" ]; then
    echo "check-manifest: the example's tooling deletes directory trees:" >&2
    echo "$DELETES" | cut -c1-160 | sed 's/^/  /' >&2
    FAILED=1
else
    echo "check-manifest: no recursive delete in the example's tooling."
fi

# 5. The podspec. `pod ipc spec` prints it as JSON.
if ! command -v pod > /dev/null; then
    if [ -n "${CI:-}" ]; then
        echo "check-manifest: CocoaPods is not installed on this runner; the podspec cannot be checked." >&2
        FAILED=1
    else
        echo "check-manifest: CocoaPods is not installed; the podspec was not checked."
    fi
elif ! pod ipc spec "$ROOT/$MODULE.podspec" > "$WORK/podspec.json" 2> "$WORK/podspec.log"; then
    echo "check-manifest: the podspec cannot be read. See ${WORK#"$ROOT"/}/podspec.log" >&2
    FAILED=1
elif ! python3 - "$WORK/podspec.json" "$WORK/manifest.json" <<'PY'
import json
import sys

spec = json.load(open(sys.argv[1]))
manifest = json.load(open(sys.argv[2]))
problems = []

def listed(value):
    return [value] if isinstance(value, str) else list(value or [])

for key in ("frameworks", "weak_frameworks"):
    if "XCTest" in listed(spec.get(key)):
        problems.append(f"the podspec links XCTest ({key}) into a production pod")
modes = listed(spec.get("swift_versions"))
unknown = [mode for mode in modes if mode not in ("5.0", "6.0")]
if unknown:
    problems.append(f"swift_versions lists {unknown}: only language modes that exist belong there")
if "6.0" not in modes:
    problems.append("swift_versions does not list 6.0, the language mode the package is built in")
package_platforms = {p["platformName"]: p["version"] for p in manifest.get("platforms", [])}
pod_platforms = {name: version for name, version in (spec.get("platforms") or {}).items()}
if package_platforms != pod_platforms:
    problems.append(f"platforms differ: Package.swift {package_platforms}, podspec {pod_platforms}")
for problem in problems:
    print(f"check-manifest: {problem}", file=sys.stderr)
sys.exit(1 if problems else 0)
PY
then
    FAILED=1
else
    echo "check-manifest: the podspec matches the manifest and links no test framework."
fi

# 6. The rejected shapes. Each names the error it expects in an `// expected-error:` line.
#    Every error the compiler reports for it must be that one: a typo or a missing module
#    also stops a build, and proves nothing about isolation.
#    The shapes build in a new folder on every run: a build folder kept between runs can
#    hold a plan of the library made before a source file was added, and builds from it.
REJECTED_BUILD="$(mktemp -d "$WORK/RejectedBuild.XXXXXX")"
STILL_REJECTED=0
for shape in "$ROOT"/Fixtures/Rejected/Sources/*/; do
    name="$(basename "$shape")"
    log="$WORK/rejected-$name.log"
    if [ ! -f "$shape/Shape.swift" ]; then
        echo "check-manifest: no rejected shape at ${shape#"$ROOT"/}Shape.swift" >&2
        FAILED=1
        continue
    fi
    expected="$(sed -n 's|^// expected-error: ||p' "$shape/Shape.swift" | head -1)"
    if [ -z "$expected" ]; then
        echo "check-manifest: the shape $name does not name the error it expects." >&2
        FAILED=1
    elif swift build --package-path "$ROOT/Fixtures/Rejected" --scratch-path "$REJECTED_BUILD" --target "$name" > "$log" 2>&1; then
        echo "check-manifest: the shape $name compiles now: what the compiler rejects across isolation domains has changed." >&2
        echo "  Update the documentation of the concurrency limits and this fixture." >&2
        FAILED=1
    else
        errors="$(grep -E '^/.+: error: ' "$log" || true)"
        if [ -n "$errors" ] && ! grep -vqF -- "$expected" <<< "$errors"; then
            STILL_REJECTED=$((STILL_REJECTED + 1))
        else
            echo "check-manifest: the shape $name fails, but not only with \"$expected\":" >&2
            grep -E 'error: ' "$log" | sed "s|$ROOT/||" | sort -u | cut -c1-240 | head -5 | sed 's/^/  /' >&2 || true
            FAILED=1
        fi
    fi
done
echo "check-manifest: $STILL_REJECTED cross-isolation shapes are rejected by the compiler, each with the error it names."

exit "$FAILED"

#!/bin/bash
#
# Checks what a consumer of the package gets, and what the repository's own tooling does
# on the machine of whoever runs it.
#
#   Scripts/check-manifest.sh
#
# 1. The manifest has no dependency by branch or revision, uses no plugin on any target,
#    passes no unsafe flag and does not read the environment. SwiftPM refuses a package
#    with an unstable dependency or an unsafe flag as a dependency by version, a build
#    plugin of a dependency runs in every consumer's build, and a manifest that reads the
#    environment describes more than one package.
# 2. The installation manifest of README.md works. Its URL and version are the podspec's,
#    and no platform it declares is below the package's. With only its URL pointed at a
#    throw-away tagged copy of the tracked manifest and sources, it resolves and builds: a
#    consumer that depends on the checkout by path cannot show a failure of a version
#    requirement, and only a build shows a wrong product or package name.
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
SKIPPED=""

mkdir -p "$WORK"
cd "$ROOT"

# The folders this run creates with mktemp inside $WORK. They hold a copy of the
# tracked sources and build output, and they leave with the run. The logs stay.
PROBE=""
DERIVED=""
REJECTED_BUILD=""
# A compiler job of a failed build can still write its index for a moment after the build
# has returned, so a removal is tried three times. A folder that stays is reported; it does
# not change the result of the checks.
# shellcheck disable=SC2329  # invoked by the trap below
cleanup() {
    local folder
    for folder in "$PROBE" "$DERIVED" "$REJECTED_BUILD"; do
        [ -n "$folder" ] || continue
        for _ in 1 2 3; do
            rm -rf "$folder" 2> /dev/null && break
            sleep 1
        done
        if [ -e "$folder" ]; then
            echo "check-manifest: could not remove ${folder#"$ROOT"/}. It is build output: delete it by hand." >&2
        fi
    done
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
    for setting in target.get("settings") or []:
        if "unsafeFlags" in setting.get("kind", {}):
            problems.append(f"target '{target['name']}' passes unsafe flags: {json.dumps(setting['kind'])}")
if re.search(r"ProcessInfo|getenv|\.environment\b", source):
    problems.append("Package.swift reads the environment")
for problem in problems:
    print(f"check-manifest: {problem}", file=sys.stderr)
sys.exit(1 if problems else 0)
PY
then
    FAILED=1
else
    echo "check-manifest: no unstable requirement, no plugin, no unsafe flag and no environment switch in Package.swift."
fi

# 2. The installation manifest of README.md, against a throw-away tagged copy of the tracked
#    files. The copy is named after the last component of the README's URL, as SwiftPM names
#    the package it fetches from there, so the package name the README uses must match it.
PROBE="$(mktemp -d "$WORK/version-probe.XXXXXX")"
mkdir -p "$PROBE/consumer"
# The probe repository takes nothing from the git configuration of whoever runs this:
# no signing, no hooks, no identity.
probe_git() {
    git -C "$PROBE/$COPY" \
        -c user.name=probe -c user.email=probe@example.invalid \
        -c commit.gpgsign=false -c tag.gpgSign=false -c core.hooksPath=/dev/null \
        "$@"
}
# Writes the consumer's manifest and prints the version the README asks for and the name of
# the copy.
if ! ANSWER="$(python3 - "$ROOT/README.md" "$ROOT/$MODULE.podspec" "$PROBE" "$WORK/manifest.json" <<'PY'
import json
import re
import sys

readme, podspec, probe, package_manifest = sys.argv[1:5]
blocks = re.findall(r"^```swift\n(.*?)^```$", open(readme, encoding="utf-8").read(), re.S | re.M)
manifests = [block for block in blocks if "Package(" in block]
if len(manifests) != 1:
    sys.exit(f"check-manifest: README.md has {len(manifests)} package manifests; it must have one")
requirements = re.findall(r'\.package\(url: "([^"]+)", from: "([^"]+)"\)', manifests[0])
if len(requirements) != 1:
    sys.exit("check-manifest: the manifest of README.md does not ask for the package with url: and from:")
url, version = requirements[0]
spec = open(podspec, encoding="utf-8").read()
spec_url = re.search(r":git\s*=>\s*'([^']+)'", spec)
spec_version = re.search(r"\.version\s*=\s*'([^']+)'", spec)
problems = []
if not spec_url or url != spec_url.group(1):
    problems.append(f"README.md installs from {url}, the podspec's source is {spec_url and spec_url.group(1)}")
if not spec_version or version != spec_version.group(1):
    problems.append(f"README.md asks for version {version}, the podspec is {spec_version and spec_version.group(1)}")
# The build below runs for this Mac, so it cannot see an iOS or watchOS floor: compare them here.
def version_tuple(text):
    return tuple(int(part) for part in text.split("."))
floors = {p["platformName"]: p["version"] for p in json.load(open(package_manifest)).get("platforms", [])}
declared = re.findall(r"\.(iOS|watchOS|macOS|tvOS|visionOS)\(\.v(\d+)(?:_(\d+))?\)", manifests[0])
if not declared:
    problems.append("the manifest of README.md declares no platform")
for name, major, minor in declared:
    wanted = f"{major}.{minor or 0}"
    floor = floors.get(name.lower())
    if floor is None:
        problems.append(f"README.md's manifest declares {name}, a platform the package does not declare")
    elif version_tuple(wanted) < version_tuple(floor):
        problems.append(f"README.md's manifest declares {name} {wanted}, the package needs {name} {floor}")
if problems:
    sys.exit("\n".join(f"check-manifest: {problem}" for problem in problems))
# SwiftPM names a package it fetches after the last component of its URL.
copy = re.sub(r"\.git$", "", url.rstrip("/").split("/")[-1])
with open(f"{probe}/consumer/Package.swift", "w", encoding="utf-8") as consumer:
    consumer.write(manifests[0].replace(f'url: "{url}"', f'url: "file://{probe}/{copy}"'))
print(version, copy)
PY
)"; then
    FAILED=1
else
    read -r VERSION COPY <<< "$ANSWER"
    mkdir -p "$PROBE/$COPY"
    # Without -l, rsync skips a symbolic link and says so only in a warning: the counts below
    # would show it.
    git ls-files -z -- Package.swift Sources | xargs -0 -I{} rsync -Rl {} "$PROBE/$COPY/"
    COPIED="$(cd "$PROBE/$COPY" && find . \( -type f -o -type l \) | wc -l | tr -d ' ')"
    TRACKED="$(git ls-files -- Package.swift Sources | wc -l | tr -d ' ')"
    if [ "$COPIED" -eq "$TRACKED" ]; then
        # SwiftPM resolves the copy as soon as it reads the consumer's manifest.
        probe_git init -q
        probe_git add -A
        probe_git commit -q -m probe
        probe_git tag "$VERSION"
    fi
    if [ "$COPIED" -ne "$TRACKED" ]; then
        echo "check-manifest: the tagged copy holds $COPIED of the $TRACKED tracked files of the package" >&2
        FAILED=1
    elif ! swift package --package-path "$PROBE/consumer" dump-package \
            > "$WORK/readme-manifest.json" 2> "$WORK/readme-manifest.log"; then
        echo "check-manifest: the manifest of README.md does not evaluate:" >&2
        sed 's/^/  /' "$WORK/readme-manifest.log" | head -10 >&2
        FAILED=1
    elif ! TARGETS="$(python3 -c 'import json, sys; print("\n".join(t["name"] for t in json.load(sys.stdin)["targets"]))' \
            < "$WORK/readme-manifest.json")"; then
        echo "check-manifest: the targets of the README's manifest cannot be read" >&2
        FAILED=1
    elif [ -z "$TARGETS" ]; then
        echo "check-manifest: the manifest of README.md has no target to build" >&2
        FAILED=1
    else
        # Every target of the consumer gets a source file that imports the module.
        while IFS= read -r TARGET; do
            mkdir -p "$PROBE/consumer/Sources/$TARGET"
            echo "import $MODULE" > "$PROBE/consumer/Sources/$TARGET/$TARGET.swift"
        done <<< "$TARGETS"
        if swift build --package-path "$PROBE/consumer" > "$WORK/version-build.log" 2>&1; then
            echo "check-manifest: the manifest of README.md asks for the podspec's URL and version $VERSION, and resolves and builds by version."
        else
            echo "check-manifest: the manifest of README.md does not resolve or build by version:" >&2
            ERRORS="$(grep -E "error:|cannot be used|unstable|unsafe" "$WORK/version-build.log" | cut -c1-300 | head -5 || true)"
            if [ -n "$ERRORS" ]; then
                printf '%s\n' "$ERRORS" >&2
            else
                tail -15 "$WORK/version-build.log" | sed 's/^/  /' >&2
            fi
            FAILED=1
        fi
    fi
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
    # No warning means something only if the log shows every source of the fixture compiled.
    NOT_COMPILED=""
    while IFS= read -r SOURCE; do
        if ! grep -qE "^SwiftCompile .*/$SOURCE( |$)" "$WORK/consumer-build.log"; then
            NOT_COMPILED="$NOT_COMPILED $SOURCE"
        fi
    done < <(git -C "$ROOT" ls-files 'Fixtures/Consumer/Sources/*.swift')
    WARNINGS="$(grep -F "/Fixtures/Consumer/" "$WORK/consumer-build.log" | grep -F ": warning: " | sort -u || true)"
    if [ -n "$NOT_COMPILED" ]; then
        echo "check-manifest: the build log of Fixtures/Consumer does not show these compiled:$NOT_COMPILED" >&2
        FAILED=1
    elif [ -n "$WARNINGS" ]; then
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
DELETE_PATTERN="$RECURSIVE_RM|$RM_AS_ARGUMENT|$TREE_REMOVAL|$MACHINE_FOLDER"
# The patterns must still catch the calls they are for, with the same engine as the search.
printf '%s\n' 'rm -rf ~/Library/Developer/Xcode/DerivedData' "FileUtils.rm_rf(path)" \
    "system('rm', '-r', path)" "find . -name '*.tmp' -delete" > "$WORK/delete-probe.txt"
PROBE_HITS="$(git grep --no-index -hcE "$DELETE_PATTERN" -- "$WORK/delete-probe.txt" || true)"
GREP_STATUS=0
DELETES="$(git grep -nE "$DELETE_PATTERN" -- Examples ':(exclude,glob)**/.gitignore')" || GREP_STATUS=$?
if [ "$PROBE_HITS" != "4" ]; then
    echo "check-manifest: the delete patterns match ${PROBE_HITS:-0} of the 4 calls they must catch" >&2
    FAILED=1
elif [ "$GREP_STATUS" -gt 1 ]; then
    echo "check-manifest: the search for recursive deletes failed (git grep exit $GREP_STATUS)" >&2
    FAILED=1
elif [ -n "$DELETES" ]; then
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
        SKIPPED="the podspec (CocoaPods is not installed)"
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

# Last, so that a skipped step is not lost in the middle of the output.
if [ -n "$SKIPPED" ]; then
    echo "check-manifest: not checked on this machine: $SKIPPED."
fi
exit "$FAILED"

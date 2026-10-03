#!/bin/bash
#
# Checks that the committed example project is what XcodeGen generates from its spec.
#
#   Scripts/check-example-project.sh            compare, exit 1 on any difference
#   Scripts/check-example-project.sh --update   regenerate the committed project from the spec
#
# The spec, Examples/DMActionExample/project.yml, is the source of the project.
# To change the project, change the spec and run this script with --update. It generates
# the project the same way the comparison does, in a folder named like the package, so the
# result does not depend on the name of the folder of the checkout.
#
# This is a local check. CI does not run it, because CI does not install the generator.
# The script installs nothing: it needs XcodeGen on the machine and says so when it is
# missing. It regenerates the project from a copy of the example folder and compares the
# result with the project files that are under version control.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXAMPLE="Examples/DMActionExample"
PROJECT="DMActionExample.xcodeproj"
GENERATOR_VERSION="2.45.3"
WORK="$ROOT/.build/check-example-project"

if ! command -v xcodegen > /dev/null; then
    echo "check-example-project: XcodeGen is not installed. The project was generated with $GENERATOR_VERSION." >&2
    exit 2
fi

INSTALLED="$(xcodegen --version | sed 's/^Version: //')"
if [ "$INSTALLED" != "$GENERATOR_VERSION" ]; then
    echo "check-example-project: note: the project was generated with XcodeGen $GENERATOR_VERSION," >&2
    echo "  this machine has $INSTALLED. A difference may come from the generator, not from the spec." >&2
fi

mkdir -p "$WORK"
COPY="$(mktemp -d "$WORK/copy.XXXXXX")"
# The copy is throw-away. The generator log and the difference stay next to it.
trap 'rm -rf "$COPY"' EXIT

# The example folder is copied without its project, so the generated project cannot be
# the committed one. The spec refers to the package as ../.. and the generator names the
# package reference after that folder, so the copy sits in a folder named like the module:
# the project is generated in a checkout whose folder is called DMAction.
SANDBOX="$COPY/generated/DMAction"
mkdir -p "$SANDBOX/$EXAMPLE"
rsync -a --exclude "$PROJECT" "$ROOT/$EXAMPLE/" "$SANDBOX/$EXAMPLE/"

if ! (cd "$SANDBOX/$EXAMPLE" && xcodegen generate) > "$WORK/xcodegen.log" 2>&1; then
    echo "check-example-project: XcodeGen failed. See ${WORK#"$ROOT"/}/xcodegen.log" >&2
    tail -5 "$WORK/xcodegen.log" >&2
    exit 2
fi

cp -R "$SANDBOX/$EXAMPLE/$PROJECT" "$SANDBOX/$EXAMPLE/$PROJECT.generated"

# Only tracked files are compared: Xcode writes user data into the project folder. The
# resolved versions of the packages come from resolving them, not from the generator.
mkdir -p "$COPY/committed"
(cd "$ROOT" && git ls-files -z -- "$EXAMPLE/$PROJECT" ":(exclude)$EXAMPLE/$PROJECT/project.xcworkspace/xcshareddata/swiftpm" \
    | xargs -0 -I{} rsync -R {} "$COPY/committed/")

# The generator gives the product of a package that a target does not link a new random
# identifier on every run. It is the only part of the project that is not reproducible.
for project_file in "$COPY/committed/$EXAMPLE/$PROJECT/project.pbxproj" "$SANDBOX/$EXAMPLE/$PROJECT/project.pbxproj"; do
    sed -E 's/TEMP_[0-9A-F-]{36}/TEMP_ID/g' "$project_file" > "$project_file.normalized"
    mv "$project_file.normalized" "$project_file"
done

if [ "${1:-}" = "--update" ]; then
    # The generated project, not the normalised copy. The random identifier keeps the
    # value the committed project has, so an update without a change in the spec leaves
    # the project file untouched.
    GENERATED="$SANDBOX/$EXAMPLE/$PROJECT.generated/project.pbxproj"
    KEPT_ID="$(grep -o -E 'TEMP_[0-9A-F-]{36}' "$ROOT/$EXAMPLE/$PROJECT/project.pbxproj" | head -1 || true)"
    if [ -n "$KEPT_ID" ]; then
        sed -E "s/TEMP_[0-9A-F-]{36}/$KEPT_ID/g" "$GENERATED" > "$GENERATED.kept"
        mv "$GENERATED.kept" "$GENERATED"
    fi
    rsync -a --delete --exclude xcuserdata --filter 'P /project.xcworkspace/xcshareddata/' \
        "$SANDBOX/$EXAMPLE/$PROJECT.generated/" "$ROOT/$EXAMPLE/$PROJECT/"
    echo "check-example-project: the project was regenerated from its spec: $EXAMPLE/$PROJECT"
    exit 0
fi

if diff -r "$COPY/committed/$EXAMPLE/$PROJECT" "$SANDBOX/$EXAMPLE/$PROJECT" > "$WORK/project.diff"; then
    echo "check-example-project: the project matches its spec."
    exit 0
fi

echo "check-example-project: the committed project differs from what the spec generates." >&2
echo "  '<' is the committed project, '>' is the generated one." >&2
echo "  Change $EXAMPLE/project.yml, run Scripts/check-example-project.sh --update and commit both." >&2
head -40 "$WORK/project.diff" >&2
exit 1

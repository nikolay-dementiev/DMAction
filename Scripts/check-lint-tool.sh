#!/bin/bash
#
# Proves three behaviours of Scripts/swiftlint-tool.sh that no ordinary lint run shows, because
# they fail only when two runs overlap. It needs no network and no SwiftLint: the pinned archive
# is replaced by a small fake one, and `unzip` and `curl` are shims.
#
#   Scripts/check-lint-tool.sh
#
# 1. While a run unpacks the tool, the file at the tool path stays whole, so a process that is
#    executing it, or about to, never meets a half-written binary.
# 2. Two first-time runs at once both fetch the tool and succeed.
# 3. An archive with a wrong checksum is removed and never reaches the unpack.
#
# Exit codes: 0 all three hold, 1 one does not.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=SCRIPTDIR/swiftlint-tool.sh
. "$ROOT/Scripts/swiftlint-tool.sh"

VERSION="9.9.9"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-lint-tool.XXXXXX")"
# shellcheck disable=SC2329  # invoked by the trap below
cleanup() {  # The EXIT trap below calls it. skipcq: SH-2329
    rm -rf "$WORK"
}
trap cleanup EXIT

FAILURES=0
fail() {  # <message>
    FAILURES=$((FAILURES + 1))
    echo "check-lint-tool: FAIL $1" >&2
}

# The fake archive holds one executable, `swiftlint`, that prints a word.
mkdir "$WORK/payload" "$WORK/shims"
printf '#!/bin/sh\necho whole\n' > "$WORK/payload/swiftlint"
chmod 755 "$WORK/payload/swiftlint"
(cd "$WORK/payload" && zip -q "$WORK/fake.zip" swiftlint)
SWIFTLINT_CHECKSUM="$(shasum -a 256 "$WORK/fake.zip" | cut -d ' ' -f 1)"

# Two downloads in flight wait for each other and deliver together. The one that arrived second
# keeps its curl alive a moment longer, so the other run has finished its fetch before this one
# ends: the order in which a shared part file is taken from under a run.
cat > "$WORK/shims/curl" <<SHIM
#!/bin/bash
while [ \$# -gt 0 ]; do
    case "\$1" in --output) out="\$2" ;; esac
    shift
done
touch "$WORK/curl.\$\$"
if mkdir "$WORK/first" 2> /dev/null; then late=0; else late=1; fi
for _ in \$(seq 1 50); do [ "\$(ls "$WORK"/curl.* | wc -l)" -ge 2 ] && break; sleep 0.1; done
cp "$WORK/fake.zip" "\$out"
[ "\$late" -eq 0 ] || sleep 1
SHIM
# unzip records each call. When SLOW_UNPACK is set it first writes half a file into the folder
# it was given, says so, and waits until it is released.
cat > "$WORK/shims/unzip" <<SHIM
#!/bin/bash
echo "unzip \$*" >> "$WORK/unzip.log"
if [ -n "\${SLOW_UNPACK:-}" ]; then
    while [ \$# -gt 0 ]; do
        case "\$1" in -d) dir="\$2" ;; esac
        shift
    done
    printf '#!/bin/sh\necho hal' > "\$dir/swiftlint"
    touch "$WORK/midway"
    for _ in \$(seq 1 100); do [ -e "$WORK/release" ] && break; sleep 0.1; done
    set -- -q -o "$WORK/fake.zip" swiftlint -d "\$dir"
fi
exec $(command -v unzip) "\$@"
SHIM
chmod 755 "$WORK/shims/curl" "$WORK/shims/unzip"
PATH="$WORK/shims:$PATH"

# A root with the fake archive already in place, so that only the unpack is exercised.
prepare_root() {  # <name>
    mkdir -p "$WORK/$1/.build/tools/swiftlint-$VERSION"
    cp "$WORK/fake.zip" "$WORK/$1/.build/tools/swiftlint-$VERSION/portable_swiftlint.zip"
}

# 1. The tool stays whole while another run unpacks.
prepare_root slow
TOOL="$(swiftlint_fetch "$WORK/slow" "$VERSION" check-lint-tool)"
SLOW_UNPACK=1 swiftlint_fetch "$WORK/slow" "$VERSION" check-lint-tool > /dev/null 2> "$WORK/slow.err" &
SLOW_PID=$!
for _ in $(seq 1 100); do [ -e "$WORK/midway" ] && break; sleep 0.1; done
if [ ! -e "$WORK/midway" ]; then
    fail "the slow unpack never started"
elif [ "$("$TOOL" 2>&1 || true)" != "whole" ] || ! cmp -s "$TOOL" "$WORK/payload/swiftlint"; then
    fail "the tool path held a half-written file while another run unpacked"
else
    echo "check-lint-tool: ok   the tool stays whole while another run unpacks"
fi
touch "$WORK/release"
SLOW_STATUS=0
wait "$SLOW_PID" || SLOW_STATUS=$?
if [ "$SLOW_STATUS" -ne 0 ]; then
    fail "the slow run ended with status $SLOW_STATUS: $(cat "$WORK/slow.err")"
fi

# 2. Two first-time runs at once.
mkdir -p "$WORK/both/.build/tools/swiftlint-$VERSION"
swiftlint_fetch "$WORK/both" "$VERSION" check-lint-tool > /dev/null 2> "$WORK/both-a.err" &
PID_A=$!
swiftlint_fetch "$WORK/both" "$VERSION" check-lint-tool > /dev/null 2> "$WORK/both-b.err" &
PID_B=$!
STATUS_A=0
STATUS_B=0
wait "$PID_A" || STATUS_A=$?
wait "$PID_B" || STATUS_B=$?
if [ "$STATUS_A" -ne 0 ] || [ "$STATUS_B" -ne 0 ]; then
    fail "two first-time runs ended with status $STATUS_A and $STATUS_B: $(cat "$WORK/both-a.err" "$WORK/both-b.err")"
elif [ "$("$WORK/both/.build/tools/swiftlint-$VERSION/swiftlint" 2>&1 || true)" != "whole" ]; then
    fail "the tool of the two first-time runs does not run"
else
    echo "check-lint-tool: ok   two first-time runs at once both succeed"
fi

# 3. A wrong checksum never reaches the unpack.
prepare_root wrong
: > "$WORK/unzip.log"
WRONG_STATUS=0
SWIFTLINT_CHECKSUM="0000000000000000000000000000000000000000000000000000000000000000" \
    swiftlint_fetch "$WORK/wrong" "$VERSION" check-lint-tool > /dev/null 2> /dev/null || WRONG_STATUS=$?
if [ "$WRONG_STATUS" -ne 2 ]; then
    fail "a wrong checksum ended with status $WRONG_STATUS, not 2"
elif [ -e "$WORK/wrong/.build/tools/swiftlint-$VERSION/portable_swiftlint.zip" ]; then
    fail "the archive with a wrong checksum was not removed"
elif [ -s "$WORK/unzip.log" ]; then
    fail "a wrong checksum still reached the unpack"
else
    echo "check-lint-tool: ok   a wrong checksum is removed and never unpacked"
fi

if [ "$FAILURES" -gt 0 ]; then
    echo "check-lint-tool: $FAILURES of 3 behaviours of swiftlint-tool.sh do not hold" >&2
    exit 1
fi
echo "check-lint-tool: the 3 behaviours of swiftlint-tool.sh hold."

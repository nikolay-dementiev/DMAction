#!/bin/bash
#
# Proves that the four scripts which forward to DMDevKit forward faithfully. It needs no network
# and no DMDevKit: `swift` is a shim that records how it was called, and `xcrun` and `curl` are
# shims that fail, so a script that does its own work instead of forwarding cannot reach the
# simulator or the network.
#
#   Scripts/check-wrappers.sh [<folder with the four scripts>]
#
# The folder is Scripts/ next to this script unless one is given. For each of lint.sh,
# check-lint-contract.sh, check-lint-tool.sh and prepare-simulator.sh, copied into a scratch
# repository that has a Tools/ folder, it checks that:
#
# 1. The shim is called once, as `run --quiet --package-path Tools devkit <command> <arguments>`,
#    from the root of the repository, even when the script is started in another directory. The
#    arguments reach it as they were given: plain, with a space, with a newline, empty, a star, a
#    dash, with quotes.
# 2. Started with no argument and from its own folder, it passes none, and finds the root.
# 3. The status of the shim is the status of the script: 0, 1, 2, 64, 70 and 130.
# 4. Standard output and standard error are the shim's, byte for byte, with nothing added, whatever
#    the status. The script that prints a simulator's UDID depends on this.
# 5. The script ends in an exec: the process that was started is the process of the shim, so a
#    signal sent to the script reaches devkit.
#
# Exit codes: 0 all hold, 1 one does not, 2 wrong usage or a script missing from the folder.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ "$#" -gt 1 ]; then
    echo "usage: Scripts/check-wrappers.sh [<folder with the four scripts>]" >&2
    exit 2
fi
FOLDER="${1:-$ROOT/Scripts}"
case "$FOLDER" in
    /*) ;;
    *) FOLDER="$PWD/$FOLDER" ;;
esac
STEMS="lint check-lint-contract check-lint-tool prepare-simulator"
for STEM in $STEMS; do
    if [ ! -f "$FOLDER/$STEM.sh" ]; then
        echo "check-wrappers: $FOLDER/$STEM.sh does not exist" >&2
        exit 2
    fi
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/check-wrappers.XXXXXX")"
# shellcheck disable=SC2329  # invoked by the trap below
cleanup() {  # The EXIT trap below calls it. skipcq: SH-2329
    rm -rf "$WORK"
}
trap cleanup EXIT

FAILURES=0
CHECKS=0
fail() {  # <message>
    FAILURES=$((FAILURES + 1))
    echo "check-wrappers: FAIL $1" >&2
}

mkdir "$WORK/bin" "$WORK/repo" "$WORK/repo/Scripts" "$WORK/repo/Tools" "$WORK/elsewhere"
for STEM in $STEMS; do
    cp -p "$FOLDER/$STEM.sh" "$WORK/repo/Scripts/$STEM.sh"
done
REPO="$(cd "$WORK/repo" && pwd -P)"

# The shim writes one record for each call: CALL, the physical working directory and every
# argument, each ended by a NUL byte, so that an argument with a space or a newline stays one. It
# also writes its process id, which equals the one that run() started only if the script exec'd it.
cat > "$WORK/bin/swift" <<'SHIM'
#!/bin/bash
{
    printf 'CALL\0%s\0' "$(pwd -P)"
    for ARGUMENT in "$@"; do
        printf '%s\0' "$ARGUMENT"
    done
} >> "$SHIM_LOG"
printf '%s' "$$" > "$SHIM_PID"
echo "out from the shim"
echo "err from the shim" >&2
exit "${SHIM_STATUS:-0}"
SHIM
printf '#!/bin/sh\nexit 99\n' > "$WORK/bin/xcrun"
printf '#!/bin/sh\nexit 99\n' > "$WORK/bin/curl"
chmod 755 "$WORK/bin/swift" "$WORK/bin/xcrun" "$WORK/bin/curl"

STATUS=0
# run <path of the script> <directory to start it in> <status the shim ends with> [arguments...]
# Leaves the record of the shim in $WORK/log, the streams in $WORK/stdout and $WORK/stderr, and
# the status of the script in $STATUS. A small launcher writes its process id and then execs the
# script, so that $WORK/launcher.pid can be compared with the id the shim wrote to $WORK/shim.pid.
run() {
    local script="$1" directory="$2" shim_status="$3"
    shift 3
    : > "$WORK/log"
    rm -f "$WORK/launcher.pid" "$WORK/shim.pid"
    STATUS=0
    (cd "$directory" && PATH="$WORK/bin:$PATH" SHIM_LOG="$WORK/log" SHIM_PID="$WORK/shim.pid" \
        SHIM_STATUS="$shim_status" LAUNCHER_PID="$WORK/launcher.pid" \
        sh -c 'echo $$ > "$LAUNCHER_PID"; exec "$@"' sh "$script" "$@" \
        > "$WORK/stdout" 2> "$WORK/stderr") || STATUS=$?
}

# expect <command> [arguments...]: the one record that a faithful script leaves, in $WORK/expected.
expect() {
    {
        printf 'CALL\0'
        printf '%s\0' "$REPO" run --quiet --package-path Tools devkit "$@"
    } > "$WORK/expected"
}

# Shows a record on one line, for a message.
show() {
    tr '\0' ' ' < "$1"
}

printf 'out from the shim\n' > "$WORK/expected.out"
printf 'err from the shim\n' > "$WORK/expected.err"
NEWLINE_ARGUMENT=$'two\nlines'

for STEM in $STEMS; do
    SCRIPT="$WORK/repo/Scripts/$STEM.sh"
    BEFORE=$FAILURES

    CHECKS=$((CHECKS + 1))
    run "$SCRIPT" "$WORK/elsewhere" 0 plain "two words" "$NEWLINE_ARGUMENT" "" '*' -x 'say "hi"' "it's"
    expect "$STEM" plain "two words" "$NEWLINE_ARGUMENT" "" '*' -x 'say "hi"' "it's"
    if [ "$STATUS" -ne 0 ] || ! cmp -s "$WORK/log" "$WORK/expected"; then
        fail "$STEM.sh started in another directory: expected the call [$(show "$WORK/expected")], got [$(show "$WORK/log")], status $STATUS"
    fi
    if ! cmp -s "$WORK/stdout" "$WORK/expected.out" || ! cmp -s "$WORK/stderr" "$WORK/expected.err"; then
        fail "$STEM.sh started with arguments printed [$(cat "$WORK/stdout")] on standard output and [$(cat "$WORK/stderr")] on standard error, not the output of the shim alone"
    fi

    CHECKS=$((CHECKS + 1))
    run "./$STEM.sh" "$WORK/repo/Scripts" 0
    expect "$STEM"
    if [ "$STATUS" -ne 0 ] || ! cmp -s "$WORK/log" "$WORK/expected"; then
        fail "$STEM.sh started from its own folder with no argument: expected the call [$(show "$WORK/expected")], got [$(show "$WORK/log")], status $STATUS"
    fi

    CHECKS=$((CHECKS + 1))
    for WANTED in 0 1 2 64 70 130; do
        run "$SCRIPT" "$WORK/elsewhere" "$WANTED"
        if [ "$STATUS" -ne "$WANTED" ]; then
            fail "$STEM.sh ended with status $STATUS where the shim ended with $WANTED"
        fi
        if ! cmp -s "$WORK/stdout" "$WORK/expected.out"; then
            fail "$STEM.sh printed [$(cat "$WORK/stdout")] on standard output when the shim ended with $WANTED, not the output of the shim alone"
        fi
        if ! cmp -s "$WORK/stderr" "$WORK/expected.err"; then
            fail "$STEM.sh printed [$(cat "$WORK/stderr")] on standard error when the shim ended with $WANTED, not the output of the shim alone"
        fi
    done

    CHECKS=$((CHECKS + 1))
    run "$SCRIPT" "$WORK/elsewhere" 0
    if [ "$(cat "$WORK/launcher.pid" 2> /dev/null)" != "$(cat "$WORK/shim.pid" 2> /dev/null)" ] ||
        [ ! -s "$WORK/shim.pid" ]; then
        fail "$STEM.sh did not exec swift: process $(cat "$WORK/launcher.pid" 2> /dev/null) started it and process $(cat "$WORK/shim.pid" 2> /dev/null) ran swift"
    fi

    if [ "$FAILURES" -eq "$BEFORE" ]; then
        echo "check-wrappers: ok   $STEM.sh forwards its arguments, directory, status and streams"
    fi
done

if [ "$FAILURES" -gt 0 ]; then
    echo "check-wrappers: $FAILURES failures in $CHECKS checks of 4 scripts" >&2
    exit 1
fi
echo "check-wrappers: the 4 scripts forward to devkit as they should."

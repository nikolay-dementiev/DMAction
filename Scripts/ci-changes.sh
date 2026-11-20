#!/bin/bash
#
# Decides which jobs of .github/workflows/ci.yml a pull request needs, from the paths it changes.
#
#   Scripts/ci-changes.sh <event> <base sha>   diffs HEAD against the base, prints light=... heavy=...
#   Scripts/ci-changes.sh --classify <event>   the same decision for the paths on standard input
#   Scripts/ci-changes.sh --self-test          proves the decision on fixtures and the job table on ci.yml
#
# Two groups of jobs, each answered with run or skip:
#   light  lint, docs, snippets, api, consumer, podspec: macOS without a simulator, short. They read
#          the documents (DocC, the snippet check, the manifest check, the changelog, the license).
#   heavy  test, watchos, example, floor, thread-sanitizer: they build and test the code.
#
# A change that only touches documents (*.md outside the code directories, Documentation, LICENSE)
# skips heavy. A change that only touches an inert file (.coderabbit.yaml, which no job reads) skips
# both. Every other path runs both, and so does a path nobody listed, an empty list, a diff that
# cannot be made, and every event that is not a pull request (push, schedule, workflow_dispatch and
# workflow_call, which is the release).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly LIGHT_JOBS="lint docs snippets api consumer podspec"
readonly HEAVY_JOBS="test watchos example floor thread-sanitizer"

# inert, document or code. Code is the default, and the code directories win over a *.md in them.
classify() {
    case "$1" in
        .coderabbit.yaml) echo inert ;;
        Sources/* | Tests/* | Examples/* | Fixtures/* | Tools/* | Scripts/* | .github/*) echo code ;;
        *.md | Documentation/* | LICENSE) echo document ;;
        *) echo code ;;
    esac
}

# Reads paths on standard input, takes the event as its argument, prints the two answers.
decide() {
    local event="$1" path count=0 mode=inert
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        count=$((count + 1))
        case "$(classify "$path")" in
            code) mode=code ;;
            document) [ "$mode" = code ] || mode=document ;;
            *) ;;
        esac
    done
    if [ "$event" != pull_request ] || [ "$count" -eq 0 ]; then
        mode=code
    fi
    case "$mode" in
        code) echo "light=run"; echo "heavy=run" ;;
        document) echo "light=run"; echo "heavy=skip" ;;
        *) echo "light=skip"; echo "heavy=skip" ;;
    esac
}

run_diff() {
    local event="$1" base="$2" paths
    if [ "$event" != pull_request ]; then
        printf '' | decide "$event"
        return
    fi
    # A base that is not in the clone, or no common ancestor, must run everything: a path that no
    # class lists stands for the change that could not be listed.
    if ! paths="$(git -C "$ROOT" diff --name-only "$base"...HEAD)"; then
        echo "ci-changes: git diff against $base failed, so every job runs." >&2
        paths="unlisted/unknown-change"
    fi
    printf '%s\n' "$paths" | decide "$event"
}

failures=0
expect() {
    local label="$1" event="$2" paths="$3" want="$4" got
    got="$(printf '%s\n' "$paths" | decide "$event" | tr '\n' ' ')"
    got="${got% }"
    if [ "$got" != "$want" ]; then
        echo "ci-changes self-test: $label: wanted '$want', got '$got'" >&2
        failures=$((failures + 1))
    fi
}

# Every job of ci.yml is in exactly one group and asks for its group's answer, so that a job added
# later cannot run unfiltered by accident.
check_job_table() {
    local workflow="$ROOT/.github/workflows/ci.yml" job group block names
    names="$(awk '/^jobs:/ { in_jobs = 1; next } in_jobs && /^  [a-z][a-z-]*:$/ { sub(/^  /, ""); sub(/:$/, ""); print }' "$workflow" | tr '\n' ' ')"
    for job in $names; do
        [ "$job" = changes ] && continue
        group=""
        case " $LIGHT_JOBS " in *" $job "*) group=light ;; esac
        case " $HEAVY_JOBS " in *" $job "*) group=heavy ;; esac
        if [ -z "$group" ]; then
            echo "ci-changes self-test: job '$job' of ci.yml is in neither group" >&2
            failures=$((failures + 1))
            continue
        fi
        block="$(awk -v job="$job" '$0 == "  " job ":" { on = 1; next } on && /^  [a-z][a-z-]*:$/ { exit } on { print }' "$workflow")"
        if ! printf '%s\n' "$block" | grep -q "needs.changes.outputs.$group == 'run'"; then
            echo "ci-changes self-test: job '$job' does not ask for needs.changes.outputs.$group" >&2
            failures=$((failures + 1))
        fi
    done
    for job in $LIGHT_JOBS $HEAVY_JOBS; do
        case " $names " in *" $job "*) ;; *)
            echo "ci-changes self-test: '$job' is in a group but not a job of ci.yml" >&2
            failures=$((failures + 1))
            ;;
        esac
    done
}

self_test() {
    local all="light=run heavy=run" docs="light=run heavy=skip" none="light=skip heavy=skip" path event
    for path in Sources/DMAction/X.swift Tests/DMActionTests/X.swift Package.swift Examples/DMActionExample/X.swift Scripts/lint.sh Tools/Package.swift Fixtures/Consumer/X.swift DMAction.podspec .swiftlint.yml; do
        expect "a change at $path runs every job" pull_request "$path" "$all"
    done
    expect "a change under .github runs every job" pull_request ".github/workflows/ci.yml" "$all"
    expect "a markdown file under .github runs every job" pull_request ".github/PULL_REQUEST_TEMPLATE.md" "$all"
    expect "a README alone skips the heavy jobs" pull_request "README.md" "$docs"
    expect "a document under Documentation alone skips the heavy jobs" pull_request "Documentation/Review/README.md" "$docs"
    expect "LICENSE alone skips the heavy jobs" pull_request "LICENSE" "$docs"
    expect "a markdown file in Sources is code" pull_request "Sources/DMAction/DMAction.docc/Page.md" "$all"
    expect "a README with a source file runs every job" pull_request $'README.md\nSources/DMAction/X.swift' "$all"
    expect "the source file first, the README second" pull_request $'Sources/DMAction/X.swift\nREADME.md' "$all"
    expect "a path that no class lists runs every job" pull_request "new/dir/x.bin" "$all"
    expect "the inert file alone skips every job" pull_request ".coderabbit.yaml" "$none"
    expect "the inert file with a README skips the heavy jobs" pull_request $'.coderabbit.yaml\nREADME.md' "$docs"
    expect "the inert file with a source file runs every job" pull_request $'.coderabbit.yaml\nSources/DMAction/X.swift' "$all"
    expect "an empty list runs every job" pull_request "" "$all"
    for event in push schedule workflow_dispatch workflow_call; do
        expect "the event $event runs every job whatever changed" "$event" "README.md" "$all"
        expect "the event $event runs every job for the inert file" "$event" ".coderabbit.yaml" "$all"
    done
    check_job_table
    if [ "$failures" -ne 0 ]; then
        echo "ci-changes self-test: $failures failed." >&2
        exit 1
    fi
    echo "ci-changes self-test: the decision and the job table hold."
}

case "${1-}" in
    --self-test) self_test ;;
    --classify)
        [ "$#" -eq 2 ] || { echo "usage: Scripts/ci-changes.sh --classify <event>" >&2; exit 2; }
        decide "$2"
        ;;
    "" | -*)
        echo "usage: Scripts/ci-changes.sh <event> <base sha> | --classify <event> | --self-test" >&2
        exit 2
        ;;
    *)
        [ "$#" -eq 2 ] || { echo "usage: Scripts/ci-changes.sh <event> <base sha>" >&2; exit 2; }
        run_diff "$1" "$2"
        ;;
esac

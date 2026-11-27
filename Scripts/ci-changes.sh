#!/bin/bash
#
# Decides which jobs of .github/workflows/ci.yml a pull request or a push to main needs, from the
# paths it changes.
#
#   Scripts/ci-changes.sh <event> <base> <ref>        diffs HEAD against the base, prints light=... heavy=...
#   Scripts/ci-changes.sh --classify <event> [<ref>]  the same decision for the paths on standard input
#   Scripts/ci-changes.sh --self-test                 proves the decision on fixtures and the job table on ci.yml
#
# Two groups of jobs, each answered with run or skip:
#   light  lint, docs, snippets, api, consumer: macOS without a simulator, short. They read
#          the documents (DocC, the snippet check, the manifest check, the changelog, the license).
#   heavy  test, watchos, example, thread-sanitizer: they build and test the code.
#
# A change that only touches documents (*.md outside the code directories, Documentation, LICENSE)
# skips heavy. A change that only touches an inert file (.coderabbit.yaml, which no job reads) skips
# both. Every other path runs both, and so does a path nobody listed, an empty list and a diff that
# cannot be made.
#
# Only a pull request and a push to refs/heads/main are filtered. A push is diffed from the commit
# main had before it (the base) to HEAD; a base that is empty, all zeros or not in the clone runs
# everything. Every other run starts everything: schedule, workflow_dispatch, workflow_call, a push to
# another branch, and the release, which calls this workflow from a push of a version tag (the event
# inside a called workflow is the caller's, so it reads push with a tag ref and a zero base).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly LIGHT_JOBS="lint docs snippets api consumer"
readonly HEAVY_JOBS="test watchos example thread-sanitizer"

# inert, document or code. Code is the default, and the code directories win over a *.md in them.
classify() {
    case "$1" in
        .coderabbit.yaml) echo inert ;;
        Sources/* | Tests/* | Examples/* | Fixtures/* | Tools/* | Scripts/* | .github/*) echo code ;;
        *.md | Documentation/* | LICENSE) echo document ;;
        *) echo code ;;
    esac
}

# Only a pull request and a push to main are decided from their paths.
filtered() {
    case "$1" in
        pull_request) return 0 ;;
        push) [ "${2-}" = refs/heads/main ] ;;
        *) return 1 ;;
    esac
}

# Reads paths on standard input, takes the event and the ref as its arguments, prints the two answers.
decide() {
    local event="$1" ref="${2-}" path count=0 mode=inert
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        count=$((count + 1))
        case "$(classify "$path")" in
            code) mode=code ;;
            document) [ "$mode" = code ] || mode=document ;;
            *) ;;
        esac
    done
    if ! filtered "$event" "$ref" || [ "$count" -eq 0 ]; then
        mode=code
    fi
    case "$mode" in
        code) echo "light=run"; echo "heavy=run" ;;
        document) echo "light=run"; echo "heavy=skip" ;;
        *) echo "light=skip"; echo "heavy=skip" ;;
    esac
}

# The repository is the fourth argument so that the self-test can run the real diff on a scratch one.
run_diff() {
    local event="$1" base="$2" ref="$3" repo="${4-$ROOT}" paths
    if ! filtered "$event" "$ref"; then
        printf '' | decide "$event" "$ref"
        return
    fi
    # A base that is not in the clone, or no common ancestor, must run everything: a path that no
    # class lists stands for the change that could not be listed.
    # --no-renames lists both paths of a moved file, so a source file moved into Documentation is
    # still a source change; core.quotePath=false keeps a non-ASCII path as it is, not in quotes.
    # A pull request is diffed from the merge base; a push from the commit main had before it.
    local range=("$base...HEAD")
    if [ "$event" = push ]; then
        range=("$base" HEAD)
    fi
    if [ -z "$base" ] || [[ "$base" =~ ^0+$ ]] || ! paths="$(git -C "$repo" -c core.quotePath=false diff --no-renames --name-only "${range[@]}")"; then
        echo "ci-changes: no usable diff against '$base', so every job runs." >&2
        paths="unlisted/unknown-change"
    fi
    printf '%s\n' "$paths" | decide "$event" "$ref"
}

failures=0
# The fifth argument is the ref, main by default: only a pull request or a push to main is filtered.
expect() {
    local label="$1" event="$2" paths="$3" want="$4" ref="${5-refs/heads/main}" got
    got="$(printf '%s\n' "$paths" | decide "$event" "$ref" | tr '\n' ' ')"
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
        if ! printf '%s\n' "$block" | grep -qF "if: \${{ !cancelled() && needs.changes.outputs.$group != 'skip' }}"; then
            echo "ci-changes self-test: job '$job' does not carry if: \${{ !cancelled() && needs.changes.outputs.$group != 'skip' }}" >&2
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

# Runs the real diff on a scratch repository: a source file moved into Documentation, and a document
# whose name is not ASCII.
check_real_diff() {
    local dir base
    dir="$(mktemp -d)"
    git -C "$dir" init -q
    git -C "$dir" config user.name scratch
    git -C "$dir" config user.email scratch@example.com
    mkdir -p "$dir/Sources/DMAction" "$dir/Documentation"
    echo "let value = 1" > "$dir/Sources/DMAction/Foo.swift"
    echo "text" > "$dir/README.md"
    git -C "$dir" add -A
    git -C "$dir" commit -q -m base
    base="$(git -C "$dir" rev-parse HEAD)"
    git -C "$dir" mv Sources/DMAction/Foo.swift Documentation/Foo.md
    git -C "$dir" commit -q -m moved
    expect_diff "a source file moved to Documentation/*.md runs every job" "$dir" pull_request "$base" refs/pull/1/merge "light=run heavy=run"
    expect_diff "the same move in a push to main runs every job" "$dir" push "$base" refs/heads/main "light=run heavy=run"
    git -C "$dir" reset -q --hard "$base"
    mkdir -p "$dir/Documentation"
    echo "text" > "$dir/Documentation/R$(printf '\303\251')sum$(printf '\303\251').md"
    git -C "$dir" add -A
    git -C "$dir" commit -q -m document
    expect_diff "a document with a non-ASCII name skips the heavy jobs" "$dir" pull_request "$base" refs/pull/1/merge "light=run heavy=skip"
    expect_diff "a push to main of a document skips the heavy jobs" "$dir" push "$base" refs/heads/main "light=run heavy=skip"
    expect_diff "a push of a release tag runs every job for the same document" "$dir" push "$base" refs/tags/1.2.0 "light=run heavy=run"
    expect_diff "a push with a base of zeros runs every job" "$dir" push "0000000000000000000000000000000000000000" refs/heads/main "light=run heavy=run"
    expect_diff "a push with an empty base runs every job" "$dir" push "" refs/heads/main "light=run heavy=run"
    expect_diff "a push with a base that is not in the clone runs every job" "$dir" push "1111111111111111111111111111111111111111" refs/heads/main "light=run heavy=run"
    expect_diff "a pull request with a base of zeros runs every job" "$dir" pull_request "0000000000000000000000000000000000000000" refs/pull/1/merge "light=run heavy=run"
    rm -rf "$dir"
}

expect_diff() {
    local label="$1" repo="$2" event="$3" base="$4" ref="$5" want="$6" got
    got="$(run_diff "$event" "$base" "$ref" "$repo" | tr '\n' ' ')"
    got="${got% }"
    if [ "$got" != "$want" ]; then
        echo "ci-changes self-test: $label: wanted '$want', got '$got'" >&2
        failures=$((failures + 1))
    fi
}

self_test() {
    local all="light=run heavy=run" docs="light=run heavy=skip" none="light=skip heavy=skip" path event
    for path in Sources/DMAction/X.swift Tests/DMActionTests/X.swift Package.swift Examples/DMActionExample/X.swift Scripts/lint.sh Tools/Package.swift Fixtures/Consumer/X.swift .swiftlint.yml; do
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
    for event in schedule workflow_dispatch workflow_call; do
        expect "the event $event runs every job whatever changed" "$event" "README.md" "$all"
        expect "the event $event runs every job for the inert file" "$event" ".coderabbit.yaml" "$all"
    done
    for path in Sources/DMAction/X.swift Tests/DMActionTests/X.swift Package.swift Examples/DMActionExample/X.swift Scripts/lint.sh Tools/Package.swift Fixtures/Consumer/X.swift .swiftlint.yml .github/workflows/ci.yml new/dir/x.bin; do
        expect "a push to main with a change at $path runs every job" push "$path" "$all"
    done
    expect "a push to main with a README alone skips the heavy jobs" push "README.md" "$docs"
    expect "a push to main with the inert file alone skips every job" push ".coderabbit.yaml" "$none"
    expect "a push to main with a README and a source file runs every job" push $'README.md\nSources/DMAction/X.swift' "$all"
    expect "a push to main with an empty list runs every job" push "" "$all"
    expect "a push of a release tag runs every job for a README" push "README.md" "$all" refs/tags/1.2.0
    expect "a push of a release tag runs every job for the inert file" push ".coderabbit.yaml" "$all" refs/tags/1.2.0
    expect "a push to another branch runs every job" push "README.md" "$all" refs/heads/other
    expect "a push with no ref runs every job" push "README.md" "$all" ""
    check_job_table
    check_real_diff
    if [ "$failures" -ne 0 ]; then
        echo "ci-changes self-test: $failures failed." >&2
        exit 1
    fi
    echo "ci-changes self-test: the decision and the job table hold."
}

case "${1-}" in
    --self-test) self_test ;;
    --classify)
        [ "$#" -ge 2 ] && [ "$#" -le 3 ] || { echo "usage: Scripts/ci-changes.sh --classify <event> [<ref>]" >&2; exit 2; }
        decide "$2" "${3-}"
        ;;
    "" | -*)
        echo "usage: Scripts/ci-changes.sh <event> <base> <ref> | --classify <event> [<ref>] | --self-test" >&2
        exit 2
        ;;
    *)
        [ "$#" -eq 3 ] || { echo "usage: Scripts/ci-changes.sh <event> <base> <ref>" >&2; exit 2; }
        run_diff "$1" "$2" "$3"
        ;;
esac

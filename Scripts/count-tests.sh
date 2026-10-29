#!/bin/bash
#
#   Scripts/count-tests.sh [--label <text>] <result bundle> <glob>...
#
# Checks that every test method of the files the globs name ran and passed in the result bundle.
# The CI workflow calls this path; `devkit count-tests` of DMDevKit, which Tools/Package.swift
# pins, does the work. Arguments, standard output and the exit status pass through unchanged, and
# standard error too, but for the lines that SwiftPM prints while it fetches DMDevKit on a first
# run. The script goes to the repository root first, because devkit takes the repository from the
# working directory: the globs are git pathspecs of the root, and a relative path to the bundle is
# relative to the root too (CI passes an absolute one). --quiet keeps the build progress of
# `swift run` off standard error. Scripts/check-wrappers.sh checks all of this.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 70
exec swift run --quiet --package-path Tools devkit count-tests "$@"

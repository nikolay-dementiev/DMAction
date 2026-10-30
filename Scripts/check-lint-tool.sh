#!/bin/bash
#
# Kept at this path for its callers (CI, CONTRIBUTING.md); `devkit check-lint-tool`
# of DMDevKit, which Tools/Package.swift pins, does the work. Arguments, standard output and the
# exit status pass through unchanged, and standard error too, but for the lines that SwiftPM prints
# while it fetches DMDevKit on a first run. The script goes to the repository root first, because
# devkit takes the repository from the working directory. --quiet keeps the build progress of
# `swift run` off standard error. Scripts/check-wrappers.sh checks all of this.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 70
exec swift run --quiet --package-path Tools devkit check-lint-tool "$@"

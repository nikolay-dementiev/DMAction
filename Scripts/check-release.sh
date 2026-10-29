#!/bin/bash
#
# Kept at this path for its callers (the release workflow, CONTRIBUTING.md, ENGINEERING.md);
# `devkit check-release` of DMDevKit, which Tools/Package.swift pins, does the work. Arguments,
# standard output and the exit status pass through unchanged, and standard error too, but for the
# lines that SwiftPM prints while it fetches DMDevKit on a first run. The script goes to the
# repository root first, because devkit takes the repository from the working directory.
# --quiet keeps the build progress of `swift run` off standard error. The pod version it expects
# is FROZEN_POD_VERSION of devkit.conf. Scripts/check-wrappers.sh checks all of this.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 70
exec swift run --quiet --package-path Tools devkit check-release "$@"

#!/bin/bash
#
# Kept at this path for its callers (CI, AGENTS.md, CONTRIBUTING.md).
# The work is done by `devkit check-lint-tool` of DMDevKit, which Tools/Package.swift pins.
# Arguments, standard streams and exit status pass through unchanged. The script goes to the
# repository root first, as it did before, so that it works from any directory. --quiet keeps the
# build progress of `swift run` off standard error. Scripts/check-wrappers.sh proves all of this.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 70
exec swift run --quiet --package-path Tools devkit check-lint-tool "$@"

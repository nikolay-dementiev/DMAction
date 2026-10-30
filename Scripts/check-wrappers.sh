#!/bin/bash
#
# Kept at this path for the people who run it (CONTRIBUTING.md); `devkit check-wrappers` of
# DMDevKit, which Tools/Package.swift pins, does the work, on the scripts that WRAPPERS in
# devkit.conf lists. CI calls `devkit check-wrappers` itself, so that a fault of this script
# cannot turn that check into another command. Arguments, standard output and the exit status pass
# through unchanged, and standard error too, but for the lines that SwiftPM prints while it
# fetches DMDevKit on a first run. The script goes to the repository root first, because devkit
# takes the repository from the working directory. --quiet keeps the build progress of `swift run`
# off standard error. devkit check-wrappers checks this script as well as the others.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 70
exec swift run --quiet --package-path Tools devkit check-wrappers "$@"

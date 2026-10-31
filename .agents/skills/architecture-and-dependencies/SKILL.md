---
name: architecture-and-dependencies
description: Review a change to DMAction for imports, dependencies, platform floors, where code lives and how actions are composed. Use it on any change to Sources, Package.swift, devkit.conf or the lint fixtures.
---

# Architecture and dependencies

The question of this lane: does the change keep the package what ENGINEERING.md says it is? The
lane applies the rules of the repository and states none of its own. Report each finding in the
format of [Documentation/Review/README.md](../../../Documentation/Review/README.md).

## What it checks

- An import that follows a block comment on the same line. The lint rule `domain_imports` reports
  every other import outside Foundation and `os`; this is the one case it does not see.
  (ENGINEERING.md, "Imports")
- A dependency, a plugin, an unsafe flag or a read of the environment that comes with a change of
  `Scripts/check-manifest.sh`, or a change of that check that weakens it. The check rejects them
  by name, so a dependency lands only with a change of the check in the same pull request.
  (ENGINEERING.md, "No dependency without the maintainer's approval")
  (AGENTS.md, "Add no dependency without the maintainer's approval")
- A raised platform floor or `swift-tools-version`, a `defaultIsolation` in the manifest, or a test
  framework other than XCTest. (ENGINEERING.md, "Toolchain and platforms")
- Code in the wrong folder: the plan as data in `Domain/`, the executor in `Adapters/`, the facade
  at the root. No lint rule keeps `Domain/` from naming the executor or `Adapters/` from naming the
  facade, so the reviewer does. (ENGINEERING.md, "Two folders under the facade")
- A combinator, `fallbackTo` or `retry`, that runs something instead of building a value, or that
  nests a run. (ENGINEERING.md, "Composition as data")
- A concrete action created outside the public initializers, a global configuration or a
  singleton. (ENGINEERING.md, "Composition root")
- `SWIFT_FLAGS` in `devkit.conf` and the flags in `Package.swift` that differ. No check compares
  them. (CONTRIBUTING.md, "`SWIFT_FLAGS` repeats what `Package.swift` sets")
- A lint rule added or widened without a fixture that proves that it fires on the lines that expect
  it and on no other line. (ENGINEERING.md, "The rules are proved")

## What it ignores

- What a CI script already enforces: `Scripts/lint.sh` and its rules (the imports of the library,
  the names in its hand-kept list of facade types in `Domain/`, force unwraps, process
  termination, missing documentation, formatting), `Scripts/check-manifest.sh`,
  `Scripts/check-api.sh` and `Scripts/coverage-gate.sh`.
- How a run behaves: that is the lane correctness-and-concurrency.
- The class of a change and its documentation: that is the lane public-api-and-documentation.
- The quality of a test: that is the lane test-discrimination.

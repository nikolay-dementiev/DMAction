---
name: correctness-and-concurrency
description: Review a change to DMAction for how a run delivers its result, where values cross isolation domains and whether a failure reaches the caller. Use it on any change to the executor, the plan, the async surface or a documented limit.
---

# Correctness and concurrency

The question of this lane: does a run still behave as ENGINEERING.md says it does? The lane
applies the rules of the repository and states none of its own. Report each finding in the format
of [Documentation/Review/README.md](../../../Documentation/Review/README.md).

## What it checks

- A second result delivered by one run, or a later completion that is not ignored.
  (ENGINEERING.md, "One delivery")
- `Sendable` or `@Sendable` added on the synchronous surface, or a payload that reaches the caller
  without passing through the mapper. (ENGINEERING.md, "`Sendable` only where a value leaves")
- An actor, a task or a checked continuation in `runAsync`, or a second owner of its terminal
  state. (ENGINEERING.md, "`Sendable` only where a value leaves")
- A failure that does not reach the caller through the result of the run.
  (ENGINEERING.md, "A failure reaches the caller through the result of the run")
- A change to what the library enforces or cannot promise, as written in the DocC article Running
  Actions and in the README. Hand the finding to the lane public-api-and-documentation as a change
  of behaviour. (ENGINEERING.md, "Documented limits")

## What it ignores

- What a CI script already enforces: `Scripts/lint.sh` and its rules (`no_process_termination`,
  `force_unwrapping`, `force_try`, `force_cast`, the imports, missing documentation, formatting),
  `Scripts/check-manifest.sh`, `Scripts/check-api.sh` and `Scripts/coverage-gate.sh`.
- Where code lives and which dependencies it uses: that is the lane architecture-and-dependencies.
- The class of a change and its documentation: that is the lane public-api-and-documentation.
- The quality of a test: that is the lane test-discrimination.

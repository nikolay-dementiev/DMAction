---
name: test-discrimination
description: Review the tests of a DMAction change for whether each one can fail, goes through the public API and is written the way the repository asks. Use it on any change to Tests, and on any fix or change of behaviour.
---

# Test discrimination

The question of this lane: would these tests catch the defect they claim to catch? The lane
applies the rules of the repository and states none of its own. Report each finding in the format
of [Documentation/Review/README.md](../../../Documentation/Review/README.md).

## What it checks

- A new test for which the change of the code that it fails on is not named.
  (AGENTS.md, "Every new test must be able to fail")
  (CONTRIBUTING.md, "A test must be able to fail")
  (PR template, "For each new test, the change to the code that it fails on")
- A test that reaches past the public API, for example with `@testable import`.
  (AGENTS.md, "with no `@testable import`")
  (CONTRIBUTING.md, "XCTest, through the public API only")
- A test class without a `makeSUT()` factory, or a double that asserts inside itself instead of a
  hand-written spy that records calls. (CONTRIBUTING.md, "One `makeSUT()` factory per test class")
- A name that does not say the subject, the condition and the expected result, or a test with two
  or more assertions where one has no message. (CONTRIBUTING.md, "Names say the subject")
  (CONTRIBUTING.md, "every assertion carries a message")
- A fix without a test that reproduces the defect, or a commit with the failing test that does not
  come before the commit that makes it pass. (CONTRIBUTING.md, "A fix starts with a test")
  (CONTRIBUTING.md, "The commit with a failing test comes before")
- A change of observable behaviour that no test pins. The interface checks do not see it.
  (ENGINEERING.md, "A change of behaviour is caught by a test that pins it")

## What it ignores

- What a CI script already enforces: `Scripts/lint.sh`, `Scripts/check-manifest.sh`,
  `Scripts/check-api.sh` and the coverage floor of `Scripts/coverage-gate.sh`, so the percentage of
  covered lines is not a finding.
- The design of the production code: that is the lane architecture-and-dependencies.
- How a run behaves: that is the lane correctness-and-concurrency.
- The class of a change and its documentation: that is the lane public-api-and-documentation.

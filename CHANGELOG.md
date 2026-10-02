# Changelog

All notable changes to DMAction are recorded in this file. The format follows Keep a Changelog
1.1.0, and versions follow Semantic Versioning 2.0.0.

## [1.1.0] - Unreleased

### Added

- An example app, `Examples/DMActionExample`, that uses the package from the checkout: a fetch
  retried twice that falls back to a cached quote, with the outcome and its attempt label on the
  screen. Its view model tests, a UIKit test and a UI test with the accessibility audit run in CI.

### Fixed

- The package can be added by version, for example `.package(url: ..., from: "1.1.0")`. Up to
  1.0.5 its manifest required a lint plugin by branch, and Swift Package Manager refuses a version
  requirement on a package that does that. No build plugin runs in a consumer's build any more.
- An attempt number of `UInt.max` no longer stops the host when an action is composed or when its
  primary fails. It stays at `UInt.max`.
- `retry(_:)` costs the same for any count. `retry(.max)` never returned.
- A run no longer grows the stack with the number of attempts or the length of a chain, as long
  as each producer completes on its calling thread during its call, or after its call has returned. Ten thousand
  retries, or a fallback chain ten thousand deep, overflowed the 512 KB stack of a secondary
  thread. A producer that blocks its thread until a completion it handed to another thread has
  returned still takes one level of the stack per attempt.
- A producer that calls its completion more than once no longer runs the rest of the chain again
  and no longer calls the consumer again.
- The pod no longer links XCTest, and it lists the Swift 5 and Swift 6 language modes.

### Changed

Behaviour changes. None of them changes a declaration; each one is pinned by a test.

**Attempt labels.** A success carries the `currentAttempt` of the action that was run plus the
number of attempts that failed before it in that run. A failure carries no label.

| Shape | Success at | 1.0.5 | 1.1.0 |
|---|---|---|---|
| `a` | call 1 | 0 | 0 |
| `a.retry(n)` | call 1, 2, 3, ... n + 1 | 0, 2, 3, ... n + 1 | 0, 1, 2, ... n |
| `a.fallbackTo(b)` | a, b | 0, 2 | 0, 1 |
| `a.retry(1).fallbackTo(b)` | a, a, b | 0, 2, 3 | 0, 1, 2 |
| `a.retry(3).fallbackTo(b)` | b | 5 | 4 |
| `a.fallbackTo(b.retry(2))` | a, then b on its call 1, 2, 3 | 0, 2, 2, 2 | 0, 1, 2, 3 |
| `a.retry(1).retry(1)` | call 1, 2, 3, 4 | 0, 2, 3, 3 | 0, 1, 2, 3 |
| `a.fallbackTo(b).retry(1)` | a, b, a, b | 0, 2, 3, 3 | 0, 1, 2, 3 |
| `a.fallbackTo(b.fallbackTo(c))` | a, b, c | 0, 2, 2 | 0, 1, 2 |
| `a.fallbackTo(b).fallbackTo(c)` | a, b, c | 0, 2, 3 | 0, 1, 2 |
| a left-nested chain of depth d | the last action | d + 1 | d |

**`currentAttempt` of a composed action** is the `currentAttempt` of its receiver: it is the label
of a first-try success of that action.

| Value | 1.0.5 | 1.1.0 |
|---|---|---|
| `x.fallbackTo(y).currentAttempt` | `x.currentAttempt + 1` | `x.currentAttempt` |
| `x.retry(n).currentAttempt`, n >= 1 | `x.currentAttempt + n` | `x.currentAttempt` |

**A label a producer put on its own success**, a `DMActionResultValue` with an `attemptCount`, is
replaced by the run's count everywhere. Up to 1.0.5 it was kept in three places: as the primary of
`DMActionWithFallback(currentAttempt:_:_:)`, in a third-party action used with `fallbackTo` or
`retry`, and through call syntax on a third-party action. A composed action handed to
`DMActionWithFallback(currentAttempt:_:_:)` as a closure counts as one attempt of the outer run;
build the chain with `fallbackTo` for an exact count.

**Order of a synchronous producer.** When a producer calls its completion on the thread that called
it, before it returns, the completion call now returns at once, the rest of the producer runs, and the next attempt and the
consumer follow after the producer has returned. Up to 1.0.5 the next attempt and the consumer ran
inside the completion call. A producer that blocks after its completion call until the consumer has
run now waits forever.

**At most once.** The first completion of an attempt moves the run on. Any later one is ignored and
written to the unified log at fault level. The consumer is called at most once per run. A producer
that never completes still stalls its run.

**Threads.** Unchanged: a run continues on the thread that completes an attempt, and a completion
from another thread is not made to wait for the producer's call to return.

**Composition.** `retry` reads the `action` of a third-party conformer once, not once per attempt.
`fallbackTo` copies the steps of its operands, so a chain of n actions built one `fallbackTo` at a
time costs O(n^2) copies. `retry` applied to a composite again and again nests one level per call;
such an action is safe to destroy up to 1 000 levels deep on a 512 KB stack.

**Properties of a third-party conformer.** Call syntax reads its `action` and then its
`currentAttempt`, both when the call is made. Up to 1.0.5 `currentAttempt` was read when a success
without a label arrived.

**Language mode.** The package states the Swift 6 language mode and builds with the upcoming feature
`ExistentialAny`. The source of a consumer does not change.

### Removed

- The dependency on the lint plugin package, and the environment variable that switched it on.
- The CocoaPods example project. Its Pod helper deleted the machine's Xcode DerivedData folder on
  every install. `Examples/DMActionExample` replaces it.

## [1.0.5] - 2025-03-21

### Added

- A security policy, a code of conduct and issue templates.
- A workflow that runs the tests on GitHub.

## [1.0.4] - 2025-03-14

### Added

- An example project that uses the package through Swift Package Manager or CocoaPods.

## [1.0.3] - 2025-02-25

### Changed

- A more complete README, and more tests.

## [1.0.2] - 2025-02-24

### Fixed

- The podspec.

## [1.0.1] - 2025-02-24

The first release.

# Running Actions

What a run of an action does, what a producer must do, what the library enforces, and what it
cannot promise.

## Overview

A run is one call of an action: ``DMAction/DMAction/callAsFunction(completion:)``, the
``DMAction/DMAction/action`` of a ``DMButtonAction`` or a ``DMActionWithFallback``, or
``DMAction/DMAction/simpleAction``. Building an action with ``DMAction/DMAction/fallbackTo(_:)`` or
``DMAction/DMAction/retry(_:)`` runs nothing.

### Order and threads

- The first producer is called on the calling thread, before the call that starts the run returns.
- When a producer calls its completion on the calling thread before it returns, the completion call
  returns at once and the result is kept. The rest of the producer runs, and when the producer
  returns, the next attempt or the delivery follows on the same thread. If every producer completes
  this way, the whole run finishes on the calling thread before the call that started it returns.
- When a producer calls its completion after it has returned, on any thread, the run goes on inside
  that completion call, on that thread.
- When a completion arrives on another thread while the producer is still running, that thread
  goes on at once. It never waits for the producer, which may itself be waiting for an effect of
  that completion. The calling thread stops when the producer returns.
- The consumer's completion runs where the run finished: on the calling thread when every producer
  completed on that thread during its call, otherwise on the thread of the last completion.

### Attempt labels

A success carries ``DMAction/DMAction/currentAttempt`` of the action that was run plus the number of
attempts of that run that failed before it, saturating at `UInt.max`. A failure carries no label.
``DMAction/DMAction/fallbackTo(_:)`` and ``DMAction/DMAction/retry(_:)`` keep the receiver's
`currentAttempt`, so it is the label of a first-try success.

| Action | Success at | Label |
|---|---|---|
| `a` | its first call | 0 |
| `a.retry(n)` | call 1, 2, 3, ... n + 1 | 0, 1, 2, ... n |
| `a.fallbackTo(b)` | `a`, `b` | 0, 1 |
| `a.retry(1).fallbackTo(b)` | `a`, `a`, `b` | 0, 1, 2 |
| `a.fallbackTo(b.retry(2))` | `a`, then `b` on its call 1, 2, 3 | 0, 1, 2, 3 |
| `a.fallbackTo(b).retry(1)` | `a`, `b`, `a`, `b` | 0, 1, 2, 3 |

A label that a producer put on its own value is replaced by the run's count, and the payload is
taken out of every ``DMActionResultValue`` layer and wrapped once. An action passed to
``DMActionWithFallback/init(currentAttempt:_:_:)`` as a producer is opaque: its own attempts count as
one attempt of the outer run.

## What a producer must do

1. Call its completion once per call. Extra calls are ignored, as described below.
2. Not wait, after calling its completion on the calling thread, for anything the consumer's
   completion or the next attempt does. Both run only after the producer has returned, so such a
   producer deadlocks its run. A producer that calls its completion and then keeps working delays
   the next attempt until it returns.
3. In a long chain of retries or fallbacks, not block its thread until a completion it handed to
   another thread has returned. That completion can arrive on a thread that is still inside an
   older producer call of the run and continue the run there, one level deeper on the stack for
   every attempt. A producer that completes on the calling thread during its call, or after its
   call has returned, needs no stack per attempt at any count.
4. Not rely on a thread: it runs on whatever thread the previous attempt completed on.

## What the library enforces

- **At most one result.** The first completion of an attempt moves the run on. A later completion
  of the same attempt, of an earlier attempt, or of a finished run is ignored, and the consumer's
  completion is called at most once per run. Each ignored completion writes one line at fault level
  to the unified log, subsystem `DMAction`, category `ActionRun`, where the `os` module exists.
- **No lock during a call out.** No lock is held while a producer or the consumer's completion
  runs, so a consumer can wait for a completion from another thread.
- **Independent runs.** Each run has its own state. Overlapping runs of one action, on any threads,
  each deliver once, with their own payload and label.
- **No trap.** Labels saturate at `UInt.max`, retries are counted down, and `retry(.max)` costs no
  more to build than `retry(1)`.
- **Release.** The consumer's completion is released when the run delivers, even while a producer
  keeps its own completion. The steps of the run are released after the delivery once every
  producer call of the run has returned.

These hold for ``DMButtonAction`` and ``DMActionWithFallback`` through all three ways of running
them, for call syntax on any conformer, and for a third-party conformer composed with
``DMAction/DMAction/fallbackTo(_:)``, or with ``DMAction/DMAction/retry(_:)`` and a positive count.
`retry(0)` returns the conformer itself. The ``DMAction/DMAction/action`` of a third-party
conformer called directly, after `retry(0)` too, its default ``DMAction/DMAction/simpleAction``,
and a `simpleAction` it supplies itself are its own closures: nothing guards them.

## What the library cannot promise

- **Liveness.** A producer that never completes stalls its run. Nothing times out.
- **A thread.** The consumer's completion runs on the thread where the run finished.
- **Isolation.** No closure type is `@Sendable` and no type is `Sendable`. Use an action inside one
  isolation domain. The next section shows what the compiler accepts.
- **Typed payloads.** The success type is erased to `any Copyable`.
- **Unlimited nesting of composites.** Applying ``DMAction/DMAction/retry(_:)`` to a composite again
  and again nests one level per application. Running such an action does not grow the stack;
  destroying it does, one level per application. A thousand levels are safe on the 512 KB stack of
  a secondary thread.

## Isolation in Swift 6

The compiler keeps an action and its results inside one isolation domain. In the Swift 6 language
mode:

| Use | Compiles |
|---|---|
| A main-actor type runs an action and changes its own state in the completion | Yes |
| A main-actor type builds an action from one of its own methods | Yes |
| A producer made in a main-actor method completes from a `Task` it creates | Yes |
| A producer completes from `Task.detached` | No: passing the closure as a `sending` parameter risks data races |
| A producer made outside an actor completes from a `Task` it creates | No: the same error |
| A run is bridged to `async` code with `withCheckedContinuation` | No: sending the result risks data races |
| A composed action is kept in a `static let` | No: the static property is not concurrency-safe |
| An action or a result is used as `any Sendable` | No: it does not conform to `Sendable` |

Each of these shapes is a fixture of the repository, in `Fixtures/Consumer` and
`Fixtures/Rejected`, and CI builds each one.

## When a third-party conformer's properties are read

| Call | Reads |
|---|---|
| `x.fallbackTo(y)` | `x.currentAttempt`, `x.action`, `y.action`, once each, when it is built |
| `x.retry(n)`, n > 0 | `x.currentAttempt` and `x.action`, once each, when it is built |
| `x.retry(0)` | nothing: it returns `x` |
| call syntax | `x.action`, then `x.currentAttempt`, when it is called |
| the default `simpleAction` | `x.action`, when it is called |

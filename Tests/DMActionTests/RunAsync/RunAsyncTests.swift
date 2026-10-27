import DMAction
import Dispatch
import Foundation
import XCTest

/// `runAsync` waits for the result of the guarded run of an action and hands back a mapped value
/// and the attempt label. The wait ends with the first of two events: the mapped result, or the
/// cancellation of the task. Its three costs are pinned here: the mapper runs before the terminal
/// event, so a cancellation during the mapping wins; a callback that comes after the cancellation
/// is still mapped once and dropped; and the first delivery is the claim, so that a second one is
/// never mapped.
final class RunAsyncTests: XCTestCase {
    private typealias Map = @Sendable (any Copyable) throws -> String

    /// A third-party action that completes inline with each of its payloads in turn.
    private struct InlineAction: DMAction {
        let currentAttempt: UInt
        let id = UUID()
        let payloads: [String]

        var action: ActionType {
            let payloads = payloads
            return { completion in
                for payload in payloads {
                    completion(.success(payload))
                }
            }
        }
    }

    private struct SUT {
        let probe = CompletionProbe()
        let mapped = MapCounter()

        /// The mapping of these tests: it counts its calls and tags the payload.
        var map: Map {
            let counter = mapped
            return { payload in
                counter.increment()
                return "mapped " + ((payload as? String) ?? "not a String")
            }
        }
    }

    // MARK: - The result

    func test_runAsync_synchronousSuccess_returnsMappedValueAndAttemptLabel() async throws {
        let sut = makeSUT()

        let outcome = try await InlineAction(currentAttempt: 7, payloads: ["v"]).runAsync(mapSuccess: sut.map)

        XCTAssertEqual(outcome.value, "mapped v", "the mapper gets the payload, not the wrapper of the run")
        XCTAssertEqual(outcome.attemptCount, 7, "the label starts at the base of the action")
        XCTAssertEqual(sut.mapped.count, 1, "one mapping")
    }

    func test_runAsync_afterTwoFailedAttempts_returnsTheRunsLabel() async throws {
        let sut = makeSUT()
        let producer = ProducerSpy.succeeding(onCall: 3)

        let outcome = try await producer.action.retry(2).runAsync(mapSuccess: sut.map)

        XCTAssertEqual(outcome.value, "mapped value", "the payload of the third call")
        XCTAssertEqual(outcome.attemptCount, 2, "two attempts failed before the success")
        XCTAssertEqual(producer.callCount, 3, "the retries ran inside the one wait")
    }

    func test_runAsync_withTheLargestLabel_keepsIt() async throws {
        let sut = makeSUT()

        let outcome = try await InlineAction(currentAttempt: .max, payloads: ["v"]).runAsync(mapSuccess: sut.map)

        XCTAssertEqual(outcome.attemptCount, .max, "the label saturates and is not reset")
    }

    func test_runAsync_whenTheProducerFails_throwsTheSameError() async {
        let sut = makeSUT()
        let failure = MarkedError()

        let thrown = await thrownError {
            try await ProducerSpy.alwaysFailing(with: failure).action.runAsync(mapSuccess: sut.map)
        }

        XCTAssertTrue((thrown as? MarkedError) === failure, "the error of the producer, by identity")
        XCTAssertEqual(sut.mapped.count, 0, "a failure is not mapped")
    }

    func test_runAsync_whenTheMappingThrows_throwsItsErrorAndStartsNoRetry() async {
        let producer = ProducerSpy.succeeding(onCall: 1)
        let failure = MarkedError()

        let thrown = await thrownError {
            try await producer.action.retry(2).runAsync { _ in throw failure }
        }

        XCTAssertTrue((thrown as? MarkedError) === failure, "the error of the mapping, by identity")
        XCTAssertEqual(producer.callCount, 1, "a mapping error ends the run: no retry starts")
    }

    func test_runAsync_customConformerDuplicateCallbacks_deliversOnce() async throws {
        let sut = makeSUT()

        let outcome = try await InlineAction(currentAttempt: 0, payloads: ["first", "second"])
            .runAsync(mapSuccess: sut.map)

        XCTAssertEqual(outcome.value, "mapped first", "the first completion wins")
        XCTAssertEqual(sut.mapped.count, 1, "the second completion is not mapped: the guarded call ignores it")
    }

    // MARK: - Cancellation

    func test_runAsync_cancelBeforeRegistration_completesWithCancellation() async {
        let sut = makeSUT()
        let probe = sut.probe
        let map = sut.map
        let task = Task { () async throws -> DMActionOutcome<String> in
            while !Task.isCancelled {
                await Task.yield()
            }
            return try await DMButtonAction { probe.record($0) }.runAsync(mapSuccess: map)
        }

        task.cancel()
        let result = await task.result

        XCTAssertTrue(isCancellation(result), "a task cancelled at entry throws CancellationError")
        XCTAssertEqual(probe.callCount, 0, "no producer starts for a cancelled task")
        XCTAssertEqual(sut.mapped.count, 0, "nothing is mapped")
    }

    func test_runAsync_whenTheProducerReturnsWithoutCompleting_cancellationEndsTheWait() async {
        let sut = makeSUT()
        let probe = sut.probe
        let map = sut.map
        let task = Task { try await DMButtonAction { probe.record($0) }.runAsync(mapSuccess: map) }
        let producerRan = await waitForProducerCalls(probe)

        task.cancel()
        let result = await task.result

        XCTAssertTrue(producerRan, "the producer was called once and kept its completion")
        XCTAssertTrue(isCancellation(result), "cancellation ends the wait with CancellationError")
        XCTAssertEqual(sut.mapped.count, 0, "nothing arrived to map")
    }

    func test_runAsync_callbackAfterCancellation_doesNotResumeAgain() async {
        let sut = makeSUT()
        let probe = sut.probe
        let map = sut.map
        let task = Task { try await DMButtonAction { probe.record($0) }.runAsync(mapSuccess: map) }
        let producerRan = await waitForProducerCalls(probe)
        task.cancel()
        let result = await task.result

        if producerRan {
            probe.complete(.success("late"))
            probe.complete(.failure(MarkedError()))
        }

        XCTAssertTrue(isCancellation(result), "the wait ended with the cancellation and stays ended")
        XCTAssertEqual(sut.mapped.count, 1, "the late success is mapped once and dropped; a second late completion is ignored")
    }

    func test_runAsync_whenTheProducerCancelsTheTaskThenCompletes_returnsTheValue() async {
        let sut = makeSUT()
        let map = sut.map
        let task = Task { () async throws -> DMActionOutcome<String> in
            let action = DMButtonAction { completion in
                withUnsafeCurrentTask { $0?.cancel() }
                completion(.success("v"))
            }
            return try await action.runAsync(mapSuccess: map)
        }

        let result = await task.result

        guard case .success(let outcome) = result else {
            return XCTFail("a completion that arrived before the wait began is not replaced by the cancellation")
        }
        XCTAssertEqual(outcome.value, "mapped v", "the value, deterministically")
    }

    func test_runAsync_whenCancelledWhileTheMapperRuns_throwsCancellationAndTheMapperRunsOnce() async {
        let sut = makeSUT()
        let probe = sut.probe
        let counter = sut.mapped
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        let map: Map = { _ in
            counter.increment()
            entered.signal()
            release.wait()
            return "dropped"
        }
        let task = Task { try await DMButtonAction { probe.record($0) }.runAsync(mapSuccess: map) }
        let producerRan = await waitForProducerCalls(probe)
        guard producerRan else {
            return XCTFail("the producer was not called, so no mapping can start")
        }
        let completing = BackgroundCaller {
            probe.complete(.success("v"))
            finished.signal()
        }
        completing.start()
        await block { entered.wait() }

        task.cancel()
        let result = await task.result
        release.signal()
        await block { finished.wait() }

        XCTAssertTrue(isCancellation(result), "the cancellation wins over a completion that is still being mapped")
        XCTAssertEqual(counter.count, 1, "the mapper ran once and its result was dropped")
    }

    // MARK: - Threads and overlap

    func test_runAsync_whenTheCallbackComesFromAnotherThread_returnsTheValue() async throws {
        let sut = makeSUT()
        let probe = sut.probe
        let map = sut.map
        let task = Task { try await DMButtonAction { probe.record($0) }.runAsync(mapSuccess: map) }
        guard await waitForProducerCalls(probe) else {
            return XCTFail("the producer was not called")
        }

        let completing = BackgroundCaller { probe.complete(.success("v")) }
        completing.start()
        let outcome = try await task.value

        XCTAssertEqual(outcome.value, "mapped v", "the value of the completion from the other thread")
    }

    func test_runAsync_twoOverlappingRuns_deliverTheirOwnValues() async throws {
        let sut = makeSUT()
        let probe = sut.probe
        let map = sut.map
        let first = Task { try await DMButtonAction { probe.record($0) }.runAsync(mapSuccess: map) }
        guard await waitForProducerCalls(probe, count: 1) else {
            return XCTFail("the first producer was not called")
        }
        let second = Task { try await DMButtonAction { probe.record($0) }.runAsync(mapSuccess: map) }
        guard await waitForProducerCalls(probe, count: 2) else {
            return XCTFail("the second producer was not called")
        }

        probe.complete(.success("b"), at: 1)
        probe.complete(.success("a"), at: 0)
        let secondOutcome = try await second.value
        let firstOutcome = try await first.value

        XCTAssertEqual(firstOutcome.value, "mapped a", "the first run gets its own completion")
        XCTAssertEqual(secondOutcome.value, "mapped b", "the second run gets its own completion")
    }

    @MainActor
    func test_runAsync_fromTheMainActor_startsTheFirstProducerOnTheMainThread() async throws {
        let sut = makeSUT()
        var startedOnMain = false
        let action = DMButtonAction { completion in
            startedOnMain = Thread.isMainThread
            completion(.success("v"))
        }

        _ = try await action.runAsync(mapSuccess: sut.map)

        XCTAssertTrue(startedOnMain, "the first producer runs on the calling thread, as the guarded call promises")
    }

    // MARK: - Helpers

    private func makeSUT() -> SUT {
        SUT()
    }

    private func thrownError(_ run: () async throws -> DMActionOutcome<String>) async -> (any Error)? {
        do {
            _ = try await run()
            return nil
        } catch {
            return error
        }
    }

    private func isCancellation(_ result: Result<DMActionOutcome<String>, any Error>) -> Bool {
        if case .failure(let error) = result {
            return error is CancellationError
        }
        return false
    }

    /// Waits until the producer was called `count` times, for five seconds at most. The deadline
    /// bounds a failing run; it orders nothing.
    private func waitForProducerCalls(_ probe: CompletionProbe, count: Int = 1) async -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while probe.callCount < count, Date() < deadline {
            await Task.yield()
        }
        return probe.callCount == count
    }

    /// Runs a blocking wait on a dispatch thread, so that the test does not hold a thread of the
    /// cooperative pool.
    private func block(_ wait: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                wait()
                continuation.resume()
            }
        }
    }
}

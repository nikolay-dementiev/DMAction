import DMAction
import DMCore
import DMCoreTesting
import XCTest

/// What a run tells its tracing value: the interval of the run, one interval for each attempt,
/// and an event for each retry, fallback and ignored completion.
final class RunSignpostTests: XCTestCase {
    private typealias Call = TracingSpy.Call

    // MARK: - Attempts

    func test_run_whenTheFirstAttemptSucceeds_recordsOneAttemptInsideTheRun() {
        let (sut, consumer) = makeSUT()

        ProducerSpy.succeeding(onCall: 1).action.callAsFunction(tracing: sut, completion: consumer.receive)

        XCTAssertEqual(sut.calls, [
            .begin("run", .number(0), interval: 0),
            .begin("attempt", .number(0), interval: 1),
            .end("attempt", .none, interval: 1),
            .end("run", .label("success"), interval: 0)
        ], "the attempt opens and closes inside the run")
        XCTAssertEqual(consumer.count, 1, "one delivery")
    }

    func test_run_whenARetrySucceeds_recordsTheRetryBetweenTheAttempts() {
        let (sut, consumer) = makeSUT()
        let action = ProducerSpy.succeeding(onCall: 2).action.retry(1)

        action.callAsFunction(tracing: sut, completion: consumer.receive)

        XCTAssertEqual(sut.calls, [
            .begin("run", .number(0), interval: 0),
            .begin("attempt", .number(0), interval: 1),
            .end("attempt", .none, interval: 1),
            .event("retry", .number(1)),
            .begin("attempt", .number(1), interval: 2),
            .end("attempt", .none, interval: 2),
            .end("run", .label("success"), interval: 0)
        ], "the event carries the number of the attempt that starts")
        XCTAssertEqual(consumer.count, 1, "one delivery")
    }

    func test_run_whenTheFallbackSucceeds_recordsTheFallbackBetweenTheAttempts() {
        let (sut, consumer) = makeSUT()
        let action = ProducerSpy.alwaysFailing().action.fallbackTo(ProducerSpy.succeeding(onCall: 1).action)

        action.callAsFunction(tracing: sut, completion: consumer.receive)

        XCTAssertEqual(sut.calls, fallbackCalls, "a move to the next step is a fallback")
        XCTAssertEqual(consumer.count, 1, "one delivery")
    }

    func test_run_whenEveryAttemptFails_recordsEachMoveAndEndsAsAFailure() {
        let (sut, consumer) = makeSUT()
        let action = ProducerSpy.alwaysFailing().action
            .fallbackTo(ProducerSpy.alwaysFailing().action)
            .retry(1)

        action.callAsFunction(tracing: sut, completion: consumer.receive)

        XCTAssertEqual(sut.calls, [
            .begin("run", .number(0), interval: 0),
            .begin("attempt", .number(0), interval: 1),
            .end("attempt", .none, interval: 1),
            .event("fallback", .number(1)),
            .begin("attempt", .number(1), interval: 2),
            .end("attempt", .none, interval: 2),
            .event("retry", .number(2)),
            .begin("attempt", .number(2), interval: 3),
            .end("attempt", .none, interval: 3),
            .event("fallback", .number(3)),
            .begin("attempt", .number(3), interval: 4),
            .end("attempt", .none, interval: 4),
            .end("run", .label("failure"), interval: 0)
        ], "the repeated unit is a retry, the next step inside it a fallback")
        XCTAssertNotNil(consumer.lastError, "the run delivered the failure")
    }

    func test_run_whenAnAttemptCompletesOnAnotherThread_recordsTheSameCalls() {
        let (sut, consumer) = makeSUT()
        let delivered = expectation(description: "delivered")
        let primary = DMButtonAction { completion in
            BackgroundCaller { completion(.failure(MarkedError())) }.start()
        }
        let action = primary.fallbackTo(ProducerSpy.succeeding(onCall: 1).action)

        action.callAsFunction(tracing: sut) { result in
            consumer.receive(result)
            delivered.fulfill()
        }
        wait(for: [delivered], timeout: 10)

        XCTAssertEqual(sut.calls, fallbackCalls, "the intervals close on the thread that completes")
        XCTAssertEqual(consumer.count, 1, "one delivery")
    }

    func test_run_whenAnAttemptNeverCompletes_leavesItsIntervalOpen() {
        let (sut, consumer) = makeSUT()
        let producer = ProducerSpy(script: [.hold])

        producer.action.callAsFunction(tracing: sut, completion: consumer.receive)

        XCTAssertEqual(sut.calls, [
            .begin("run", .number(0), interval: 0),
            .begin("attempt", .number(0), interval: 1)
        ], "an open attempt is what a trace shows of a producer that never completes")
        XCTAssertEqual(consumer.count, 0, "no delivery")
    }

    func test_run_whenItDelivers_endsTheRunIntervalBeforeTheConsumerRuns() {
        let (sut, _) = makeSUT()
        var seenByTheConsumer: [Call] = []

        ProducerSpy.succeeding(onCall: 1).action.callAsFunction(tracing: sut) { _ in
            seenByTheConsumer = sut.calls
        }

        XCTAssertEqual(
            seenByTheConsumer.last,
            .end("run", .label("success"), interval: 0),
            "what the consumer does is not part of the run"
        )
    }

    // MARK: - Ignored completions

    func test_run_whenAProducerCompletesTwice_recordsTheIgnoredCompletion() {
        let (sut, consumer) = makeSUT()
        let action = DMButtonAction { completion in
            completion(.success("first"))
            completion(.success("second"))
        }

        action.callAsFunction(tracing: sut, completion: consumer.receive)

        XCTAssertEqual(sut.calls, [
            .begin("run", .number(0), interval: 0),
            .begin("attempt", .number(0), interval: 1),
            .end("attempt", .none, interval: 1),
            .event("ignoredCompletion", .none),
            .end("run", .label("success"), interval: 0)
        ], "the extra completion is an event, and it closes nothing")
        XCTAssertEqual(consumer.count, 1, "one delivery")
    }

    // MARK: - Numbers

    func test_run_whenTheActionStartsCountingAboveZero_reportsTheAttemptLabels() {
        let (sut, consumer) = makeSUT()
        let action = DMActionWithFallback(
            currentAttempt: 5,
            ProducerSpy.alwaysFailing().produce,
            ProducerSpy.succeeding(onCall: 1).produce
        )

        action.callAsFunction(tracing: sut, completion: consumer.receive)

        XCTAssertEqual(sut.calls, [
            .begin("run", .number(5), interval: 0),
            .begin("attempt", .number(5), interval: 1),
            .end("attempt", .none, interval: 1),
            .event("fallback", .number(6)),
            .begin("attempt", .number(6), interval: 2),
            .end("attempt", .none, interval: 2),
            .end("run", .label("success"), interval: 0)
        ], "the numbers are the ones the attempt labels count with")
        XCTAssertEqual(consumer.lastLabel, 6, "the label of the success is the number of its attempt")
    }

    func test_run_whenTheCountIsTheLargestItCanHold_reportsTheLargestSignpostNumber() {
        let (sut, consumer) = makeSUT()
        let action = DMActionWithFallback(
            currentAttempt: .max,
            ProducerSpy.alwaysFailing().produce,
            ProducerSpy.succeeding(onCall: 1).produce
        )

        action.callAsFunction(tracing: sut, completion: consumer.receive)

        // `UInt` is 32 bits wide on arm64_32, where its largest value fits a signpost number.
        let largest = TraceDetail.number(Int64(clamping: UInt.max))
        XCTAssertEqual(sut.calls, [
            .begin("run", largest, interval: 0),
            .begin("attempt", largest, interval: 1),
            .end("attempt", .none, interval: 1),
            .event("fallback", largest),
            .begin("attempt", largest, interval: 2),
            .end("attempt", .none, interval: 2),
            .end("run", .label("success"), interval: 0)
        ], "a count above the range of a signpost number stays at its largest value")
        XCTAssertEqual(consumer.count, 1, "one delivery")
    }

    // MARK: - Async

    func test_runAsync_whenTheFirstAttemptSucceeds_recordsTheRun() async throws {
        let sut = makeSUT().sut
        let action = DMButtonAction { completion in completion(.success("value")) }

        _ = try await action.runAsync(tracing: sut) { _ in true }

        XCTAssertEqual(sut.calls, [
            .begin("run", .number(0), interval: 0),
            .begin("attempt", .number(0), interval: 1),
            .end("attempt", .none, interval: 1),
            .end("run", .label("success"), interval: 0)
        ], "the async surface starts the same run")
    }

    // MARK: - Helpers

    private func makeSUT() -> (sut: TracingSpy, consumer: ConsumerSpy) {
        (TracingSpy(), ConsumerSpy())
    }

    /// A primary that fails and a fallback that succeeds, each on its first call.
    private var fallbackCalls: [Call] {
        [
            .begin("run", .number(0), interval: 0),
            .begin("attempt", .number(0), interval: 1),
            .end("attempt", .none, interval: 1),
            .event("fallback", .number(1)),
            .begin("attempt", .number(1), interval: 2),
            .end("attempt", .none, interval: 2),
            .end("run", .label("success"), interval: 0)
        ]
    }
}

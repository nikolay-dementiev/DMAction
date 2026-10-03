import DMAction
import XCTest

/// Pins on which thread a run continues after a producer completes: on the calling thread
/// when the completion comes during the call, and on the completing thread otherwise.
final class ThreadCharacterizationTests: XCTestCase {
    /// What the primary, the fallback and the consumer did. A broken run could deliver from two
    /// threads, so it is written under a lock and read once every thread that could still
    /// deliver has returned from its call to the completion.
    private struct Record {
        var primaryCalls = 0
        var fallbackCalls = 0
        var fallbackThread: Thread?
        var deliveryThread: Thread?
        var results: [DMButtonAction.ResultType] = []
    }

    func test_run_whenAProducerCompletesDuringItsCall_continuesOnTheCallingThread() {
        let (record, fallback) = makeSUT()
        let primary = DMButtonAction { completion in
            record.withLock { $0.primaryCalls += 1 }
            completion(.failure(MarkedError()))
        }

        primary.fallbackTo(fallback).action { result in
            Self.receive(result, in: record)
        }

        let seen = record.withLock { $0 }
        assertOneDeliveryOfTheFallback(seen)
        XCTAssertTrue(seen.fallbackThread === Thread.current, "the fallback runs on the calling thread")
        XCTAssertTrue(seen.deliveryThread === Thread.current, "and so does the delivery")
    }

    func test_run_whenACompletionArrivesOnAnotherThreadAfterTheCall_continuesOnThatThread() throws {
        let (record, fallback) = makeSUT()
        var kept: ((DMButtonAction.ResultType) -> Void)?
        let primary = DMButtonAction { completion in
            record.withLock { $0.primaryCalls += 1 }
            kept = completion
        }
        let completionReturned = expectation(description: "the completing thread's call to the completion returned")
        primary.fallbackTo(fallback).action { result in
            Self.receive(result, in: record)
        }
        let held = try XCTUnwrap(kept, "the primary kept its completion")

        let caller = BackgroundCaller {
            held(.failure(MarkedError()))
            completionReturned.fulfill()
        }
        caller.start()
        guard XCTWaiter.wait(for: [completionReturned], timeout: 5) == .completed else {
            return XCTFail("the completing thread did not return from the completion")
        }

        let seen = record.withLock { $0 }
        assertOneDeliveryOfTheFallback(seen)
        XCTAssertNotNil(caller.thread, "the completing thread")
        XCTAssertTrue(seen.fallbackThread === caller.thread, "the fallback runs on the completing thread")
        XCTAssertTrue(seen.deliveryThread === caller.thread, "and so does the delivery")
    }

    func test_run_whenACompletionArrivesOnAnotherThreadDuringTheCall_continuesThereWithoutWaiting() {
        let fallbackStarted = DispatchSemaphore(value: 0)
        let (record, fallback) = makeSUT(whenTheFallbackRuns: { fallbackStarted.signal() })
        let completers = DispatchGroup()
        var caller: BackgroundCaller?
        var waitForTheFallback: DispatchTimeoutResult?
        let primary = DMButtonAction { completion in
            record.withLock { $0.primaryCalls += 1 }
            completers.enter()
            let background = BackgroundCaller {
                completion(.failure(MarkedError()))
                completers.leave()
            }
            caller = background
            background.start()
            // A producer may wait for an effect of its own completion before it returns.
            waitForTheFallback = fallbackStarted.wait(timeout: .now() + 5)
        }

        primary.fallbackTo(fallback).action { result in
            Self.receive(result, in: record)
        }
        guard completers.wait(timeout: .now() + 10) == .success else {
            return XCTFail("a completing thread did not return from the completion")
        }

        let seen = record.withLock { $0 }
        XCTAssertEqual(waitForTheFallback, .success, "the fallback started while the primary was still in its call")
        assertOneDeliveryOfTheFallback(seen)
        XCTAssertNotNil(caller?.thread, "the completing thread")
        XCTAssertTrue(seen.fallbackThread === caller?.thread, "the fallback runs on the completing thread")
        XCTAssertTrue(seen.deliveryThread === caller?.thread, "and so does the delivery")
    }

    /// The same with the run started on a background thread, so that neither thread is the main
    /// one: the calling thread is told apart by identity.
    func test_run_whenABackgroundCallIsCompletedFromAnotherBackgroundThread_continuesThereWithoutWaiting() {
        let fallbackStarted = DispatchSemaphore(value: 0)
        let (record, fallback) = makeSUT(whenTheFallbackRuns: { fallbackStarted.signal() })
        let callReturned = expectation(description: "the call that started the run returned")
        let completers = DispatchGroup()
        var completer: BackgroundCaller?
        var waitForTheFallback: DispatchTimeoutResult?
        let primary = DMButtonAction { completion in
            record.withLock { $0.primaryCalls += 1 }
            completers.enter()
            let background = BackgroundCaller {
                completion(.failure(MarkedError()))
                completers.leave()
            }
            completer = background
            background.start()
            waitForTheFallback = fallbackStarted.wait(timeout: .now() + 5)
        }

        BackgroundCaller {
            primary.fallbackTo(fallback).action { result in
                Self.receive(result, in: record)
            }
            callReturned.fulfill()
        }
        .start()
        guard XCTWaiter.wait(for: [callReturned], timeout: 10) == .completed else {
            return XCTFail("the call that started the run did not return")
        }
        guard completers.wait(timeout: .now() + 10) == .success else {
            return XCTFail("a completing thread did not return from the completion")
        }

        let seen = record.withLock { $0 }
        XCTAssertEqual(waitForTheFallback, .success, "the fallback started while the primary was still in its call")
        assertOneDeliveryOfTheFallback(seen)
        XCTAssertNotNil(completer?.thread, "the completing thread")
        XCTAssertTrue(seen.fallbackThread === completer?.thread, "the fallback runs on the completing thread")
        XCTAssertTrue(seen.deliveryThread === completer?.thread, "and so does the delivery")
    }

    // MARK: - Helpers

    /// A fallback that succeeds and records the thread it ran on.
    private func makeSUT(whenTheFallbackRuns: @escaping () -> Void = {}) -> (record: Locked<Record>, fallback: DMButtonAction) {
        let record = Locked(Record())
        let fallback = DMButtonAction { completion in
            record.withLock {
                $0.fallbackCalls += 1
                $0.fallbackThread = Thread.current
            }
            whenTheFallbackRuns()
            completion(.success("fallback"))
        }
        return (record, fallback)
    }

    private static func receive(_ result: DMButtonAction.ResultType, in record: Locked<Record>) {
        record.withLock {
            $0.deliveryThread = Thread.current
            $0.results.append(result)
        }
    }

    /// The primary ran once and failed, so the fallback ran once and its success was delivered
    /// once, labelled 1.
    private func assertOneDeliveryOfTheFallback(_ record: Record, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(record.primaryCalls, 1, "the primary ran once", file: file, line: line)
        XCTAssertEqual(record.fallbackCalls, 1, "the fallback ran once", file: file, line: line)
        XCTAssertEqual(record.results.count, 1, "one delivery", file: file, line: line)
        XCTAssertEqual(
            record.results.first.flatMap(ConsumerSpy.text(of:)), "fallback",
            "the success of the fallback", file: file, line: line
        )
        XCTAssertEqual(record.results.first?.attemptCount, 1, "labelled after one failed attempt", file: file, line: line)
    }
}

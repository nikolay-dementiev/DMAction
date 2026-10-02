import DMAction
import XCTest

/// Pins on which thread a run continues after a producer completes: on the calling thread
/// when the completion comes during the call, and on the completing thread otherwise.
final class ThreadCharacterizationTests: XCTestCase {
    /// The threads that the fallback and the consumer ran on.
    private final class Threads {
        var fallback: Thread?
        var delivery: Thread?
    }

    func test_run_whenAProducerCompletesDuringItsCall_continuesOnTheCallingThread() {
        let (threads, fallback) = makeSUT()
        let primary = DMButtonAction { completion in
            completion(.failure(MarkedError()))
        }

        primary.fallbackTo(fallback).action { _ in
            threads.delivery = Thread.current
        }

        XCTAssertTrue(threads.fallback === Thread.current, "the fallback runs on the calling thread")
        XCTAssertTrue(threads.delivery === Thread.current, "and so does the delivery")
    }

    func test_run_whenACompletionArrivesOnAnotherThreadAfterTheCall_continuesOnThatThread() throws {
        let (threads, fallback) = makeSUT()
        let primary = ProducerSpy(script: [.hold])
        let delivered = expectation(description: "the consumer completion ran")
        primary.action.fallbackTo(fallback).action { _ in
            threads.delivery = Thread.current
            delivered.fulfill()
        }
        let held = try XCTUnwrap(primary.heldCompletions.first, "the primary kept its completion")

        let caller = BackgroundCaller {
            held(.failure(MarkedError()))
        }
        caller.start()
        wait(for: [delivered], timeout: 5)

        XCTAssertNotNil(caller.thread, "the completing thread")
        XCTAssertTrue(threads.fallback === caller.thread, "the fallback runs on the completing thread")
        XCTAssertTrue(threads.delivery === caller.thread, "and so does the delivery")
    }

    func test_run_whenACompletionArrivesOnAnotherThreadDuringTheCall_continuesThereWithoutWaiting() {
        let fallbackStarted = DispatchSemaphore(value: 0)
        let (threads, fallback) = makeSUT(whenTheFallbackRuns: { fallbackStarted.signal() })
        let delivered = expectation(description: "the consumer completion ran")
        var caller: BackgroundCaller?
        var waitForTheFallback: DispatchTimeoutResult?
        let primary = DMButtonAction { completion in
            let background = BackgroundCaller {
                completion(.failure(MarkedError()))
            }
            caller = background
            background.start()
            // A producer may wait for an effect of its own completion before it returns.
            waitForTheFallback = fallbackStarted.wait(timeout: .now() + 5)
        }

        primary.fallbackTo(fallback).action { _ in
            threads.delivery = Thread.current
            delivered.fulfill()
        }
        wait(for: [delivered], timeout: 10)

        XCTAssertEqual(waitForTheFallback, .success, "the fallback started while the primary was still in its call")
        XCTAssertNotNil(caller?.thread, "the completing thread")
        XCTAssertTrue(threads.fallback === caller?.thread, "the fallback runs on the completing thread")
        XCTAssertTrue(threads.delivery === caller?.thread, "and so does the delivery")
    }

    /// The same with the run started on a background thread, so that neither thread is the main
    /// one: the calling thread is told apart by identity.
    func test_run_whenABackgroundCallIsCompletedFromAnotherBackgroundThread_continuesThereWithoutWaiting() {
        let fallbackStarted = DispatchSemaphore(value: 0)
        let (threads, fallback) = makeSUT(whenTheFallbackRuns: { fallbackStarted.signal() })
        let delivered = expectation(description: "the consumer completion ran")
        let callReturned = expectation(description: "the call that started the run returned")
        var completer: BackgroundCaller?
        var waitForTheFallback: DispatchTimeoutResult?
        let primary = DMButtonAction { completion in
            let background = BackgroundCaller {
                completion(.failure(MarkedError()))
            }
            completer = background
            background.start()
            waitForTheFallback = fallbackStarted.wait(timeout: .now() + 5)
        }

        BackgroundCaller {
            primary.fallbackTo(fallback).action { _ in
                threads.delivery = Thread.current
                delivered.fulfill()
            }
            callReturned.fulfill()
        }
        .start()
        wait(for: [delivered, callReturned], timeout: 10)

        XCTAssertEqual(waitForTheFallback, .success, "the fallback started while the primary was still in its call")
        XCTAssertNotNil(completer?.thread, "the completing thread")
        XCTAssertTrue(threads.fallback === completer?.thread, "the fallback runs on the completing thread")
        XCTAssertTrue(threads.delivery === completer?.thread, "and so does the delivery")
    }

    // MARK: - Helpers

    /// A fallback that succeeds and records the thread it ran on.
    private func makeSUT(whenTheFallbackRuns: @escaping () -> Void = {}) -> (threads: Threads, fallback: DMButtonAction) {
        let threads = Threads()
        let fallback = DMButtonAction { completion in
            threads.fallback = Thread.current
            whenTheFallbackRuns()
            completion(.success("fallback"))
        }
        return (threads, fallback)
    }
}

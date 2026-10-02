import DMAction
import XCTest

/// Pins on which thread a run continues after a producer completes: on the calling thread
/// when the completion comes during the call, and on the completing thread otherwise.
final class ThreadCharacterizationTests: XCTestCase {
    func test_run_whenAProducerCompletesDuringItsCall_continuesOnTheCallingThread() {
        var fallbackThread: Thread?
        var deliveryThread: Thread?
        let primary = DMButtonAction { completion in
            completion(.failure(MarkedError()))
        }
        let fallback = DMButtonAction { completion in
            fallbackThread = Thread.current
            completion(.success("fallback"))
        }

        primary.fallbackTo(fallback).action { _ in
            deliveryThread = Thread.current
        }

        XCTAssertTrue(fallbackThread === Thread.current, "the fallback runs on the calling thread")
        XCTAssertTrue(deliveryThread === Thread.current, "and so does the delivery")
    }

    func test_run_whenACompletionArrivesOnAnotherThreadAfterTheCall_continuesOnThatThread() throws {
        let primary = ProducerSpy(script: [.hold])
        let delivered = expectation(description: "the consumer completion ran")
        var fallbackThread: Thread?
        var deliveryThread: Thread?
        let fallback = DMButtonAction { completion in
            fallbackThread = Thread.current
            completion(.success("fallback"))
        }
        primary.action.fallbackTo(fallback).action { _ in
            deliveryThread = Thread.current
            delivered.fulfill()
        }
        let held = try XCTUnwrap(primary.heldCompletions.first, "the primary kept its completion")

        let caller = BackgroundCaller {
            held(.failure(MarkedError()))
        }
        caller.start()
        wait(for: [delivered], timeout: 5)

        XCTAssertNotNil(caller.thread, "the completing thread")
        XCTAssertTrue(fallbackThread === caller.thread, "the fallback runs on the completing thread")
        XCTAssertTrue(deliveryThread === caller.thread, "and so does the delivery")
    }

    func test_run_whenACompletionArrivesOnAnotherThreadDuringTheCall_continuesThereWithoutWaiting() {
        let fallbackStarted = DispatchSemaphore(value: 0)
        let delivered = expectation(description: "the consumer completion ran")
        var caller: BackgroundCaller?
        var waitForTheFallback: DispatchTimeoutResult?
        var fallbackThread: Thread?
        var deliveryThread: Thread?
        let primary = DMButtonAction { completion in
            let background = BackgroundCaller {
                completion(.failure(MarkedError()))
            }
            caller = background
            background.start()
            // A producer may wait for an effect of its own completion before it returns.
            waitForTheFallback = fallbackStarted.wait(timeout: .now() + 5)
        }
        let fallback = DMButtonAction { completion in
            fallbackThread = Thread.current
            fallbackStarted.signal()
            completion(.success("fallback"))
        }

        primary.fallbackTo(fallback).action { _ in
            deliveryThread = Thread.current
            delivered.fulfill()
        }
        wait(for: [delivered], timeout: 10)

        XCTAssertEqual(waitForTheFallback, .success, "the fallback started while the primary was still in its call")
        XCTAssertNotNil(caller?.thread, "the completing thread")
        XCTAssertTrue(fallbackThread === caller?.thread, "the fallback runs on the completing thread")
        XCTAssertTrue(deliveryThread === caller?.thread, "and so does the delivery")
    }
}

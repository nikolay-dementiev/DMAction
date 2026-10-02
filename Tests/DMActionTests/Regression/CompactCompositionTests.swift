import DMAction
import XCTest

/// `retry` used to build one nested action per retry before anything ran, so its cost grew
/// with the count and `retry(.max)` never returned. A composition now stores the count.
final class CompactCompositionTests: XCTestCase {
    func test_retry_withTheMaximumCountAndAnImmediateSuccess_runsTheProducerOnce() {
        let (producer, consumer) = makeSUT(script: [.success("first")])
        var retried: (any DMAction)?

        runOnAThreadOfItsOwn {
            let action = producer.action.retry(.max)
            action.action(consumer.receive)
            retried = action
        }

        XCTAssertEqual(retried?.currentAttempt, 0, "retry keeps the receiver's attempt")
        XCTAssertEqual(producer.callCount, 1, "one call")
        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(consumer.lastValue, "first", "the producer's payload")
        XCTAssertEqual(consumer.lastLabel, 0, "the label of a first-try success")
    }

    func test_retry_withTheMaximumCount_retriesEachFailureDeliveredByHand() throws {
        let (producer, consumer) = makeSUT(script: [.hold])

        runOnAThreadOfItsOwn {
            producer.action.retry(.max).action(consumer.receive)
        }
        for call in 1...5 {
            let held = try XCTUnwrap(producer.heldCompletions.last, "the completion of call \(call)")
            held(.failure(MarkedError()))
        }
        let callsAfterFiveFailures = producer.callCount
        let deliveriesAfterFiveFailures = consumer.count
        let sixth = try XCTUnwrap(producer.heldCompletions.last, "the completion of call 6")
        sixth(.success("sixth"))

        XCTAssertEqual(callsAfterFiveFailures, 6, "each failure starts the next attempt")
        XCTAssertEqual(deliveriesAfterFiveFailures, 0, "nothing is delivered while attempts remain")
        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(consumer.lastValue, "sixth", "the payload of the sixth call")
        XCTAssertEqual(consumer.lastLabel, 5, "five failed attempts before the sixth call")
    }

    // MARK: - Helpers

    private func makeSUT(script: [ProducerSpy.Outcome]) -> (producer: ProducerSpy, consumer: ConsumerSpy) {
        (ProducerSpy(script: script), ConsumerSpy())
    }

    /// Runs `work` on a thread of its own and waits five seconds at most, so that a `retry` that
    /// builds one action per retry fails this test instead of hanging the whole run.
    private func runOnAThreadOfItsOwn(_ work: @escaping () -> Void) {
        let finished = expectation(description: "the work finished")
        BackgroundCaller {
            work()
            finished.fulfill()
        }
        .start()
        wait(for: [finished], timeout: 5)
    }
}

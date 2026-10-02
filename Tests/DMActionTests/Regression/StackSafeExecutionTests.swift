import DMAction
import XCTest

/// A run used to nest a few calls per attempt, so a long run overflowed the stack of the
/// thread it ran on. It now runs its attempts in a loop. Each test runs on a thread with the
/// 512 KB stack that a secondary thread gets by default.
final class StackSafeExecutionTests: XCTestCase {
    private static let smallStack = 512 * 1024
    private static let depth = 10_000

    func test_retry_withTenThousandRetriesOnASmallStack_callsTheProducerTenThousandAndOneTimes() {
        let errors = (0...Self.depth).map { _ in MarkedError() }
        let producer = ProducerSpy(script: errors.map { .failure($0) })
        let consumer = ConsumerSpy()

        runOnASmallStack {
            producer.action.retry(UInt(Self.depth)).action(consumer.receive)
        }

        XCTAssertEqual(producer.callCount, Self.depth + 1, "the first attempt and ten thousand retries")
        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertTrue(consumer.lastError as? MarkedError === errors.last, "the error of the last attempt")
    }

    func test_fallbackTo_chainedTenThousandDeepToTheLeftOnASmallStack_runsEveryProducerOnce() {
        let (spies, consumer) = makeSUT()

        runOnASmallStack {
            var chain: any DMAction = spies[0].action
            for spy in spies.dropFirst() {
                chain = chain.fallbackTo(spy.action)
            }
            chain.action(consumer.receive)
        }

        XCTAssertTrue(spies.allSatisfy { $0.callCount == 1 }, "every producer runs once")
        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(consumer.lastValue, "last", "the last producer delivers")
        XCTAssertEqual(consumer.lastLabel, UInt(Self.depth), "ten thousand failed attempts before the last")
    }

    func test_fallbackTo_chainedTenThousandDeepToTheRightOnASmallStack_runsEveryProducerOnce() {
        let (spies, consumer) = makeSUT()

        runOnASmallStack {
            var chain: any DMAction = spies[Self.depth].action
            for spy in spies.dropLast().reversed() {
                chain = spy.action.fallbackTo(chain)
            }
            chain.action(consumer.receive)
        }

        XCTAssertTrue(spies.allSatisfy { $0.callCount == 1 }, "every producer runs once")
        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(consumer.lastValue, "last", "the last producer delivers")
        XCTAssertEqual(consumer.lastLabel, UInt(Self.depth), "ten thousand failed attempts before the last")
    }

    /// `retry` applied to a composite, again and again, nests one plan per call. Running such
    /// an action does not grow the stack; destroying it does, by one level per call. The
    /// documented promise is 1 000 levels on a 512 KB stack. Measured on macOS: about 1 900
    /// levels in a debug build, between 2 000 and 4 000 in a release build.
    func test_retry_appliedAThousandTimesToACompositeOnASmallStack_runsAndIsDestroyed() {
        let producer = ProducerSpy(script: [.success("value")])
        let consumer = ConsumerSpy()

        runOnASmallStack {
            var action: any DMAction = producer.action.fallbackTo(DMButtonAction { $0(.success("fallback")) })
            for _ in 0..<1_000 {
                action = action.retry(1)
            }
            action.action(consumer.receive)
        }

        XCTAssertEqual(producer.callCount, 1, "one call")
        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(consumer.lastLabel, 0, "the label of a first-try success")
    }

    // MARK: - Helpers

    /// Every producer fails except the last one, which succeeds with "last".
    private func makeSUT() -> (spies: [ProducerSpy], consumer: ConsumerSpy) {
        let spies = (0...Self.depth).map { index in
            index == Self.depth ? ProducerSpy(script: [.success("last")]) : ProducerSpy.alwaysFailing()
        }
        return (spies, ConsumerSpy())
    }

    /// Runs `work` on a new thread with a 512 KB stack and waits until it has finished.
    private func runOnASmallStack(_ work: @escaping () -> Void) {
        let finished = expectation(description: "the work on the small stack finished")
        BackgroundCaller(stackSize: Self.smallStack) {
            work()
            finished.fulfill()
        }
        .start()
        wait(for: [finished], timeout: 120)
    }
}

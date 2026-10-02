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
        XCTAssertEqual(consumer.lastLabel, UInt(Self.depth) + 1, "the legacy label of a left-nested chain")
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
        XCTAssertEqual(consumer.lastLabel, 2, "the legacy label of a right-nested chain")
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

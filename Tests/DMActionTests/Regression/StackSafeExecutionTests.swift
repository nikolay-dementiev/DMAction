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
        let (producer, consumer) = makeSUT(script: errors.map { .failure($0) })

        runOnASmallStack {
            producer.action.retry(UInt(Self.depth)).action(consumer.receive)
        }

        XCTAssertEqual(producer.callCount, Self.depth + 1, "the first attempt and ten thousand retries")
        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertTrue(consumer.lastError as? MarkedError === errors.last, "the error of the last attempt")
    }

    /// Two threads, each with a small stack, hand the attempts back and forth: every completion
    /// arrives on the other thread, after the producer has returned from its call. It proves that
    /// such a completion goes on with the run every time. It cannot show stack growth: on this
    /// path no run nests a call, even a recursive one, because every producer returns at once. The
    /// small stacks guard against a design that would wait inside a call.
    func test_retry_withTenThousandRetriesCompletedOnAnotherThreadAfterEachCall_callsTheProducerTenThousandAndOneTimes() {
        let first = SerialThread(stackSize: Self.smallStack)
        let second = SerialThread(stackSize: Self.smallStack)
        let firstThread = first.start()
        _ = second.start()
        let calls = LockedCounter()
        let failures = LockedCounter()
        let delivered = expectation(description: "the run delivered")
        let producer = DMButtonAction { completion in
            calls.increment()
            let returned = DispatchSemaphore(value: 0)
            (Thread.current === firstThread ? second : first).enqueue {
                returned.wait()
                completion(.failure(MarkedError()))
            }
            returned.signal()
        }

        runOnASmallStack {
            producer.retry(UInt(Self.depth)).action { result in
                if case .failure = result {
                    failures.increment()
                }
                delivered.fulfill()
            }
        }
        wait(for: [delivered], timeout: 120)
        first.stop()
        second.stop()

        XCTAssertEqual(calls.count, Self.depth + 1, "the first attempt and ten thousand retries")
        XCTAssertEqual(failures.count, 1, "one delivery, the failure of the last attempt")
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

    /// Running a composite nested twenty thousand times needs no stack per level. The action is
    /// leaked on purpose: destroying it recurses once per level, which the next test bounds.
    func test_retry_appliedTwentyThousandTimesToACompositeOnASmallStack_runsTheProducerOnce() {
        final class Keeper {
            let action: any DMAction
            init(_ action: any DMAction) { self.action = action }
        }
        let (producer, consumer) = makeSUT(script: [.success("value")])

        runOnASmallStack {
            var action: any DMAction = producer.action.fallbackTo(DMButtonAction { $0(.success("fallback")) })
            for _ in 0..<20_000 {
                action = action.retry(1)
            }
            _ = Unmanaged.passRetained(Keeper(action))
            action.action(consumer.receive)
        }

        XCTAssertEqual(producer.callCount, 1, "one call")
        XCTAssertEqual(consumer.lastLabel, 0, "the label of a first-try success")
    }

    /// `retry` applied to a composite, again and again, nests one plan per call. Running such
    /// an action does not grow the stack; destroying it does, by one level per call. The test
    /// pins 1 000 levels, about half of the smallest limit measured. Measured by raising the
    /// nesting until the process stopped with SIGBUS, with Swift 6.3.3 on macOS 26.5, arm64:
    /// 1 800 levels passed and 2 000 failed in a debug build, 2 000 passed and 4 000 failed in a
    /// release build. CI also runs this test with Swift 6.0 and 6.1.
    func test_retry_appliedAThousandTimesToACompositeOnASmallStack_runsAndIsDestroyed() {
        let (producer, consumer) = makeSUT(script: [.success("value")])

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

    private func makeSUT(script: [ProducerSpy.Outcome]) -> (producer: ProducerSpy, consumer: ConsumerSpy) {
        (ProducerSpy(script: script), ConsumerSpy())
    }

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

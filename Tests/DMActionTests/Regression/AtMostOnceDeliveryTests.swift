import DMAction
import OSLog
import XCTest

/// A producer that completed more than once used to continue its run once per completion:
/// the rest of the chain ran again and the consumer was called again. Now the first
/// completion of an attempt wins and the consumer is called at most once per run. A producer
/// that never completes still stalls its run: this is at most once, not a promise of an answer.
final class AtMostOnceDeliveryTests: XCTestCase {
    /// A third-party action whose own closure completes twice.
    private struct TwiceCompletingAction: DMAction {
        let currentAttempt: UInt = 0
        let id = UUID()
        let action: ActionType = { completion in
            completion(.success("first"))
            completion(.success("second"))
        }
    }

    private struct SUT {
        let producer: ProducerSpy
        let fallback: ProducerSpy
        let consumer = ConsumerSpy()
    }

    /// What one run of the concurrent test delivered.
    private struct Delivery: Equatable {
        let run: Int
        let text: String?
        let label: UInt?
    }

    private static let runKey = "DMActionTests.run"

    // MARK: - Two completions before the call returns

    func test_run_whenAProducerSucceedsTwice_deliversTheFirstSuccessOnce() {
        let sut = makeSUT()
        let action = DMButtonAction { completion in
            completion(.success("first"))
            completion(.success("second"))
        }

        action.action(sut.consumer.receive)

        XCTAssertEqual(sut.consumer.count, 1, "one delivery")
        XCTAssertEqual(sut.consumer.lastValue, "first", "the first completion wins")
    }

    func test_fallbackTo_whenThePrimaryFailsThenSucceeds_deliversOnlyTheFallbacksResult() {
        let sut = makeSUT()
        let primary = DMButtonAction { completion in
            completion(.failure(MarkedError()))
            completion(.success("late"))
        }

        primary.fallbackTo(sut.fallback.action).action(sut.consumer.receive)

        XCTAssertEqual(sut.fallback.callCount, 1, "the fallback runs once")
        XCTAssertEqual(sut.consumer.count, 1, "one delivery")
        XCTAssertEqual(sut.consumer.lastValue, "fallback", "the late success is ignored")
    }

    func test_fallbackTo_whenThePrimarySucceedsThenFails_deliversOnlyTheSuccess() {
        let sut = makeSUT()
        let primary = DMButtonAction { completion in
            completion(.success("primary"))
            completion(.failure(MarkedError()))
        }

        primary.fallbackTo(sut.fallback.action).action(sut.consumer.receive)

        XCTAssertEqual(sut.fallback.callCount, 0, "the late failure starts no fallback")
        XCTAssertEqual(sut.consumer.count, 1, "one delivery")
        XCTAssertEqual(sut.consumer.lastValue, "primary", "the first completion wins")
    }

    func test_run_whenAKeptResultIsFollowedByACompletionFromAnotherThread_ignoresTheSecond() {
        let sut = makeSUT()
        var secondCompletion: DispatchTimeoutResult?
        let primary = DMButtonAction { completion in
            completion(.failure(MarkedError()))
            let finished = DispatchSemaphore(value: 0)
            BackgroundCaller {
                completion(.success("late"))
                finished.signal()
            }
            .start()
            secondCompletion = finished.wait(timeout: .now() + 5)
        }

        primary.fallbackTo(sut.fallback.action).action(sut.consumer.receive)

        XCTAssertEqual(secondCompletion, .success, "the second completion returned before the call did")
        XCTAssertEqual(sut.fallback.callCount, 1, "the fallback runs once, after the first completion")
        XCTAssertEqual(sut.consumer.count, 1, "one delivery")
        XCTAssertEqual(sut.consumer.lastValue, "fallback", "the late success is ignored")
    }

    // MARK: - Completions after the attempt moved on

    func test_run_whenACompletionArrivesAfterTheNextAttemptStarted_ignoresIt() throws {
        let sut = makeSUT(producer: [.hold], fallback: [.hold])

        sut.producer.action.fallbackTo(sut.fallback.action).action(sut.consumer.receive)
        let primaryCompletion = try XCTUnwrap(sut.producer.heldCompletions.first, "the primary kept its completion")
        primaryCompletion(.failure(MarkedError()))
        let fallbackCompletion = try XCTUnwrap(sut.fallback.heldCompletions.first, "the fallback kept its completion")
        primaryCompletion(.success("late"))
        let deliveriesAfterTheLateCompletion = sut.consumer.count
        fallbackCompletion(.success("fallback"))

        XCTAssertEqual(deliveriesAfterTheLateCompletion, 0, "the late completion of the primary delivers nothing")
        XCTAssertEqual(sut.producer.callCount + sut.fallback.callCount, 2, "nothing runs again")
        XCTAssertEqual(sut.consumer.count, 1, "one delivery")
        XCTAssertEqual(sut.consumer.lastValue, "fallback", "the fallback's result")
    }

    func test_run_whenACompletionArrivesAfterTheRunFinished_ignoresIt() throws {
        let sut = makeSUT(producer: [.hold])

        sut.producer.action.retry(1).action(sut.consumer.receive)
        let completion = try XCTUnwrap(sut.producer.heldCompletions.first, "the producer kept its completion")
        completion(.success("first"))
        completion(.success("again"))
        completion(.failure(MarkedError()))

        XCTAssertEqual(sut.producer.callCount, 1, "a late failure starts no retry")
        XCTAssertEqual(sut.consumer.count, 1, "one delivery")
        XCTAssertEqual(sut.consumer.lastValue, "first", "the first completion wins")
    }

    func test_run_whenTheConsumerWaitsForALateCompletionFromAnotherThread_doesNotHoldItUp() throws {
        let sut = makeSUT(producer: [.hold])
        var lateCompletion: DispatchTimeoutResult?
        sut.producer.action.action { result in
            sut.consumer.receive(result)
            guard let held = sut.producer.heldCompletions.first else {
                return
            }
            let returned = DispatchSemaphore(value: 0)
            BackgroundCaller {
                held(.failure(MarkedError()))
                returned.signal()
            }
            .start()
            lateCompletion = returned.wait(timeout: .now() + 2)
        }
        let completion = try XCTUnwrap(sut.producer.heldCompletions.first, "the producer kept its completion")

        completion(.success("first"))

        XCTAssertEqual(lateCompletion, .success, "the run holds no lock while the consumer runs")
        XCTAssertEqual(sut.consumer.count, 1, "one delivery")
    }

    func test_run_whenTwoCompletionsAreIgnored_writesOneFaultToTheUnifiedLogForEach() throws {
        guard #available(macOS 12, iOS 15, watchOS 8, tvOS 15, *) else {
            throw XCTSkip("Reading the log of this process needs OSLogStore")
        }
        // The lines are counted between two markers of this test. Neither a position nor a date
        // separated them from the lines of the tests before: the store returned those too.
        let marker = UUID().uuidString
        let markers = Logger(subsystem: "DMActionTests", category: "AtMostOnceDeliveryTests")
        let action = DMButtonAction { completion in
            completion(.success("first"))
            completion(.success("second"))
            completion(.failure(MarkedError()))
        }

        markers.notice("start \(marker, privacy: .public)")
        action.action { _ in }
        markers.notice("end \(marker, privacy: .public)")

        let entries = try OSLogStore(scope: .currentProcessIdentifier)
            .getEntries(matching: NSPredicate(format: "subsystem IN %@", ["DMAction", "DMActionTests"]))
            .compactMap { $0 as? OSLogEntryLog }
        let start = try XCTUnwrap(entries.firstIndex { $0.composedMessage == "start \(marker)" }, "the start marker")
        let end = try XCTUnwrap(entries.firstIndex { $0.composedMessage == "end \(marker)" }, "the end marker")
        let faults = entries[start..<end].filter {
            $0.subsystem == "DMAction" && $0.level == .fault && $0.composedMessage.contains("completed more than once")
        }
        XCTAssertEqual(faults.count, 2, "one fault line for each of the two ignored completions")
    }

    // MARK: - Lifetime

    func test_run_afterDelivery_releasesTheConsumerWhileAProducerKeepsItsCompletion() {
        final class Token {}
        weak var weakToken: Token?
        var kept: ((DMButtonAction.ResultType) -> Void)?
        do {
            let token = Token()
            weakToken = token
            let action = DMButtonAction { completion in
                kept = completion
                completion(.success("value"))
            }
            action.action { _ in
                _ = token
            }
        }

        XCTAssertNotNil(kept, "the producer still holds its completion")
        XCTAssertNil(weakToken, "what the consumer captured is released after the delivery")
    }

    /// The boundary of the release: after the delivery, once every producer call of the run has
    /// returned. Here the producer completes inside its call, the call returns, and the action
    /// goes out of scope. A producer call still on a stack would keep its cursor, and with it
    /// the frames and the plan, until it returns.
    func test_run_afterDeliveryOnceEveryProducerCallHasReturned_releasesThePlanWhileAProducerKeepsItsCompletion() {
        final class Token {}
        weak var weakToken: Token?
        var kept: ((DMButtonAction.ResultType) -> Void)?
        do {
            let token = Token()
            weakToken = token
            let action = DMButtonAction { completion in
                _ = token
                kept = completion
                completion(.success("value"))
            }
            action.action { _ in }
        }

        XCTAssertNotNil(kept, "the producer still holds its completion")
        XCTAssertNil(weakToken, "the plan, and the producer in it, are released with the action")
    }

    // MARK: - Call syntax on a third-party action

    func test_callSyntax_onACustomActionThatCompletesTwice_deliversOnce() {
        let sut = makeSUT()
        let action = TwiceCompletingAction()

        action(completion: sut.consumer.receive)

        XCTAssertEqual(sut.consumer.count, 1, "call syntax delivers once")
        XCTAssertEqual(sut.consumer.lastValue, "first", "the first completion wins")
        XCTAssertEqual(sut.consumer.lastLabel, 0, "labelled with the action's attempt")
    }

    // MARK: - Many threads: exact counts first, then the Thread Sanitizer

    /// The runs share one action, and each fails a different number of times: a count shared
    /// between runs would give a run the label of another. Four threads complete each attempt
    /// together. A thread knows the run it serves from its thread dictionary, so the producer
    /// can tell the runs apart.
    func test_run_whenManyThreadsCompleteEachAttemptTogether_givesEveryRunItsOwnPayloadAndLabel() {
        let runs = 400
        let threadsPerAttempt = 4
        let calls = Locked<[Int: Int]>([:])
        let deliveries = Locked<[Delivery]>([])
        let completions = DispatchGroup()
        let primary = DMButtonAction { completion in
            let run = Self.run(of: Thread.current)
            let call = calls.withLock { counts in
                counts[run, default: 0] += 1
                return counts[run, default: 0]
            }
            let outcome: DMButtonAction.ResultType =
                call <= Self.failures(ofRun: run) ? .failure(MarkedError()) : .success("run \(run)")
            // The threads wait at a gate until all of them exist, then complete together.
            let ready = DispatchGroup()
            let gate = DispatchSemaphore(value: 0)
            for _ in 0..<threadsPerAttempt {
                completions.enter()
                ready.enter()
                BackgroundCaller {
                    Self.mark(Thread.current, withRun: run)
                    ready.leave()
                    _ = gate.wait(timeout: .now() + 5)
                    completion(outcome)
                    completions.leave()
                }
                .start()
            }
            _ = ready.wait(timeout: .now() + 5)
            for _ in 0..<threadsPerAttempt {
                gate.signal()
            }
        }
        let fallback = DMButtonAction { completion in
            completion(.success("fallback \(Self.run(of: Thread.current))"))
        }
        let action = primary.retry(2).fallbackTo(fallback)

        for run in 0..<runs {
            Self.mark(Thread.current, withRun: run)
            action.action { result in
                let delivery = Delivery(run: run, text: ConsumerSpy.text(of: result), label: result.attemptCount)
                deliveries.withLock { $0.append(delivery) }
            }
        }
        Thread.current.threadDictionary.removeObject(forKey: Self.runKey)

        XCTAssertEqual(completions.wait(timeout: .now() + 60), .success, "every completion call returned")
        let byRun = Dictionary(grouping: deliveries.withLock { $0 }, by: \.run)
        let wrong = (0..<runs).filter { byRun[$0] != [Self.expectedDelivery(ofRun: $0)] }
        XCTAssertEqual(wrong, [], "every run delivers once, with its own payload and label")
    }

    // MARK: - Helpers

    /// Run n fails n % 4 times. The fetch and its two retries make three attempts, so a run
    /// that fails three times gets the fallback.
    private static func failures(ofRun run: Int) -> Int {
        run % 4
    }

    private static func expectedDelivery(ofRun run: Int) -> Delivery {
        let failures = failures(ofRun: run)
        let text = failures < 3 ? "run \(run)" : "fallback \(run)"
        return Delivery(run: run, text: text, label: UInt(failures))
    }

    private static func mark(_ thread: Thread, withRun run: Int) {
        thread.threadDictionary[runKey] = run
    }

    /// -1 for a thread no run marked, so that a mix-up shows as a wrong delivery.
    private static func run(of thread: Thread) -> Int {
        thread.threadDictionary[runKey] as? Int ?? -1
    }

    private func makeSUT(
        producer: [ProducerSpy.Outcome] = [.hold],
        fallback: [ProducerSpy.Outcome] = [.success("fallback")]
    ) -> SUT {
        SUT(producer: ProducerSpy("producer", script: producer), fallback: ProducerSpy("fallback", script: fallback))
    }
}

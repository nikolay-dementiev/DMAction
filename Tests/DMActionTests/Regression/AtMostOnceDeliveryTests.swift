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
        let primaryCalls = LockedCounter()
        var secondCompletion: DispatchTimeoutResult?
        let primary = DMButtonAction { completion in
            primaryCalls.increment()
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
        XCTAssertEqual(primaryCalls.count, 1, "the primary ran once")
        XCTAssertEqual(sut.fallback.callCount, 1, "the fallback runs once, after the first completion")
        XCTAssertEqual(sut.consumer.count, 1, "one delivery")
        XCTAssertEqual(sut.consumer.lastValue, "fallback", "the late success is ignored")
        XCTAssertEqual(sut.consumer.lastLabel, 1, "labelled after the primary's failure")
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

    /// A request that timed out and answered late: the retry has started, then the first
    /// attempt's answer arrives.
    func test_retry_whenAnEarlierAttemptCompletesAfterItsRetryStarted_ignoresIt() throws {
        let sut = makeSUT(producer: [.hold])

        sut.producer.action.retry(1).action(sut.consumer.receive)
        let first = try XCTUnwrap(sut.producer.heldCompletions.first, "the first attempt kept its completion")
        first(.failure(MarkedError()))
        let callsAfterTheFailure = sut.producer.callCount
        first(.success("late"))
        let deliveriesAfterTheLateSuccess = sut.consumer.count
        let second = try XCTUnwrap(sut.producer.heldCompletions.last, "the retry kept its completion")
        second(.success("retry"))

        XCTAssertEqual(callsAfterTheFailure, 2, "the failure started the retry")
        XCTAssertEqual(deliveriesAfterTheLateSuccess, 0, "the late success of the first attempt delivers nothing")
        XCTAssertEqual(sut.producer.callCount, 2, "nothing runs again")
        XCTAssertEqual(sut.consumer.count, 1, "one delivery")
        XCTAssertEqual(sut.consumer.lastValue, "retry", "the retry's result")
        XCTAssertEqual(sut.consumer.lastLabel, 1, "one failed attempt before it")
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
        // A retry, so that a late failure the run did not ignore would call the producer again.
        sut.producer.action.retry(1).action { result in
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
        XCTAssertEqual(sut.producer.callCount, 1, "the producer ran once")
        XCTAssertEqual(sut.consumer.count, 1, "one delivery")
        XCTAssertEqual(sut.consumer.lastValue, "first", "the first completion's payload")
        XCTAssertEqual(sut.consumer.lastLabel, 0, "the label of a first-try success")
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

        // An entry may reach the store a moment after it was written: read until the end marker
        // is there, three reads at most. One read takes seconds, so a deadline would allow one.
        var entries: [OSLogEntryLog] = []
        for _ in 0..<3 {
            entries = try OSLogStore(scope: .currentProcessIdentifier)
                .getEntries(matching: NSPredicate(format: "subsystem IN %@", ["DMAction", "DMActionTests"]))
                .compactMap { $0 as? OSLogEntryLog }
            if entries.contains(where: { $0.composedMessage == "end \(marker)" }) {
                break
            }
        }
        let start = try XCTUnwrap(entries.firstIndex { $0.composedMessage == "start \(marker)" }, "the start marker")
        let end = try XCTUnwrap(entries.firstIndex { $0.composedMessage == "end \(marker)" }, "the end marker")
        let lines = entries[start..<end].filter { $0.subsystem == "DMAction" }
        let faults = lines.filter { $0.level == .fault && $0.composedMessage.contains("completed more than once") }
        XCTAssertEqual(faults.count, 2, "one fault line for each of the two ignored completions")
        XCTAssertEqual(Set(lines.map(\.category)), ["ActionRun"], "in the category the documentation names")
    }

    // MARK: - Lifetime

    /// Work a producer hands over, to be finished later.
    private final class Pending {
        var work: (() -> Void)?
    }

    /// A class conformer whose producer refers to it without retaining it and finishes later.
    private final class DeferredConformer: DMAction {
        let currentAttempt: UInt = 0
        let id = UUID()
        let payload = "deferred"
        private let pending: Pending

        init(pending: Pending) {
            self.pending = pending
        }

        var action: ActionType {
            { [unowned self] completion in
                pending.work = { [unowned self] in
                    completion(.success(payload))
                }
            }
        }
    }

    /// Call syntax keeps its receiver until the delivery, as 1.0.5 did. The deferred work runs
    /// only while the receiver lives, so a released receiver fails the test instead of trapping.
    func test_callSyntax_onAClassConformerReleasedWhileItsCallIsOutstanding_keepsItUntilTheDelivery() {
        let pending = Pending()
        let consumer = ConsumerSpy()
        weak var weakReceiver: DeferredConformer?
        do {
            let receiver = DeferredConformer(pending: pending)
            weakReceiver = receiver
            receiver(completion: consumer.receive)
        }
        let aliveWhileOutstanding = weakReceiver != nil
        if aliveWhileOutstanding {
            pending.work?()
        }
        let releasedAfterTheDelivery = weakReceiver == nil
        pending.work = nil

        XCTAssertTrue(aliveWhileOutstanding, "the receiver lives while its call is outstanding")
        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(consumer.lastValue, "deferred", "the receiver's payload")
        XCTAssertTrue(releasedAfterTheDelivery, "the receiver is released after the delivery, though the producer keeps its work")
    }

    /// A class conformer that keeps its own run's completion, and with it the run.
    private final class CompletionKeepingConformer: DMAction {
        let currentAttempt: UInt = 0
        let id = UUID()
        var kept: ((ResultType) -> Void)?

        var action: ActionType {
            { [unowned self] completion in
                kept = completion
            }
        }
    }

    /// The run keeps the receiver until it delivers, and the receiver keeps the run through the
    /// completion it stores. The delivery breaks that cycle, though the completion stays stored.
    func test_callSyntax_onAConformerThatKeepsItsOwnCompletion_releasesItAfterTheDelivery() {
        let consumer = ConsumerSpy()
        weak var weakReceiver: CompletionKeepingConformer?
        do {
            let receiver = CompletionKeepingConformer()
            weakReceiver = receiver
            receiver(completion: consumer.receive)
            receiver.kept?(.success("kept"))
        }

        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(consumer.lastValue, "kept", "the receiver's payload")
        XCTAssertNil(weakReceiver, "the delivery broke the cycle through the stored completion")
    }

    func test_run_afterDelivery_releasesTheConsumerWhileAProducerKeepsItsCompletion() {
        final class Token {}
        weak var weakToken: Token?
        var kept: ((DMButtonAction.ResultType) -> Void)?
        let consumer = ConsumerSpy()
        do {
            let token = Token()
            weakToken = token
            let action = DMButtonAction { completion in
                kept = completion
                completion(.success("value"))
            }
            action.action { result in
                _ = token
                consumer.receive(result)
            }
        }

        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(consumer.lastValue, "value", "the producer's payload")
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
        let consumer = ConsumerSpy()
        do {
            let token = Token()
            weakToken = token
            let action = DMButtonAction { completion in
                _ = token
                kept = completion
                completion(.success("value"))
            }
            action.action(consumer.receive)
        }

        XCTAssertEqual(consumer.count, 1, "one delivery")
        XCTAssertEqual(consumer.lastValue, "value", "the producer's payload")
        XCTAssertNotNil(kept, "the producer still holds its completion")
        XCTAssertNil(weakToken, "the plan, and the producer in it, are released with the action")
    }

    // MARK: - Call syntax on a third-party action

    func test_retry_withAPositiveCountOnACustomActionThatCompletesTwice_deliversOnce() {
        let sut = makeSUT()

        TwiceCompletingAction().retry(1).action(sut.consumer.receive)

        XCTAssertEqual(sut.consumer.count, 1, "the composition delivers once")
        XCTAssertEqual(sut.consumer.lastValue, "first", "the first completion wins")
    }

    /// `retry(0)` returns the action itself, so its `action` is the conformer's own closure,
    /// which nothing guards.
    func test_retry_withZeroOnACustomActionThatCompletesTwice_leavesItsOwnClosureUnguarded() {
        let sut = makeSUT()

        TwiceCompletingAction().retry(0).action(sut.consumer.receive)

        XCTAssertEqual(
            sut.consumer.deliveries.compactMap(ConsumerSpy.text(of:)), ["first", "second"],
            "both completions of its own closure arrive"
        )
    }

    func test_callSyntax_onACustomActionThatCompletesTwice_deliversOnce() {
        let sut = makeSUT()
        let action = TwiceCompletingAction()

        action(completion: sut.consumer.receive)

        XCTAssertEqual(sut.consumer.count, 1, "call syntax delivers once")
        XCTAssertEqual(sut.consumer.lastValue, "first", "the first completion wins")
        XCTAssertEqual(sut.consumer.lastLabel, 0, "labelled with the action's attempt")
    }

    // MARK: - Many threads: exact counts first, then the Thread Sanitizer

    /// Two threads wait at a barrier and complete one attempt at the same moment, thousands of
    /// times. A run that checked the attempt and took it in two steps would let both through now
    /// and then; the Thread Sanitizer does not see that, because every step holds the lock. Each
    /// time, the run must deliver the fallback's success once, labelled 1.
    func test_run_whenTwoThreadsCompleteOneAttemptAtOnce_runsTheFallbackAndDeliversOnce() {
        let left = SerialThread(stackSize: 512 * 1024)
        let right = SerialThread(stackSize: 512 * 1024)
        _ = left.start()
        _ = right.start()
        defer {
            left.stop()
            right.stop()
        }
        var wrong: [Int] = []
        for iteration in 0..<3_000 {
            let fallbackCalls = LockedCounter()
            let deliveries = Locked<[DMButtonAction.ResultType]>([])
            let producer = ProducerSpy(script: [.hold])
            let fallback = DMButtonAction { completion in
                fallbackCalls.increment()
                completion(.success("fallback"))
            }
            producer.action.fallbackTo(fallback).action { result in
                deliveries.withLock { $0.append(result) }
            }
            guard let held = producer.heldCompletions.first else {
                return XCTFail("the producer kept its completion")
            }
            let arrived = Locked(0)
            let done = DispatchGroup()
            for thread in [left, right] {
                done.enter()
                thread.enqueue {
                    arrived.withLock { $0 += 1 }
                    // A thread whose partner never arrives gives up after a second.
                    let deadline = DispatchTime.now() + 1
                    while arrived.withLock({ $0 }) < 2, DispatchTime.now() < deadline {}
                    held(.failure(MarkedError()))
                    done.leave()
                }
            }
            guard done.wait(timeout: .now() + 10) == .success else {
                return XCTFail("iteration \(iteration): a completion call did not return")
            }
            let delivered = deliveries.withLock { $0 }
            if producer.callCount != 1 || fallbackCalls.count != 1 || delivered.count != 1
                || delivered.first.flatMap(ConsumerSpy.text(of:)) != "fallback" || delivered.first?.attemptCount != 1 {
                wrong.append(iteration)
            }
        }

        XCTAssertEqual(
            wrong, [],
            "iterations where a producer ran other than once, or the run did not deliver the fallback's success, labelled 1, once"
        )
    }

    /// The runs share one action, and each fails a different number of times: a count shared
    /// between runs would give a run the label of another. Four threads complete each attempt
    /// together. A thread knows the run it serves from its thread dictionary, so the producer
    /// can tell the runs apart. The calls of both producers are counted per run as well: work
    /// done for a run and thrown away would not show in what the run delivers.
    func test_run_whenManyThreadsCompleteEachAttemptTogether_givesEveryRunItsOwnPayloadAndLabel() {
        let runs = 400
        let threadsPerAttempt = 4
        let calls = Locked<[Int: Int]>([:])
        let fallbackCalls = Locked<[Int: Int]>([:])
        let deliveries = Locked<[Delivery]>([])
        let completions = DispatchGroup()
        let primary = Self.primary(countingCallsIn: calls, completingFrom: threadsPerAttempt, in: completions)
        let fallback = DMButtonAction { completion in
            let run = Self.run(of: Thread.current)
            fallbackCalls.withLock { $0[run, default: 0] += 1 }
            completion(.success("fallback \(run)"))
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
        let primaryCalls = calls.withLock { $0 }
        let fallbacks = fallbackCalls.withLock { $0 }
        let wrongCalls = (0..<runs).filter { run in
            primaryCalls[run] != Self.expectedPrimaryCalls(ofRun: run) || fallbacks[run] != Self.expectedFallbackCalls(ofRun: run)
        }
        XCTAssertEqual(wrongCalls, [], "every run calls the primary once per attempt, and the fallback once after three failures")
        XCTAssertTrue(
            primaryCalls.keys.allSatisfy((0..<runs).contains) && fallbacks.keys.allSatisfy((0..<runs).contains),
            "every producer call served a run"
        )
    }

    // MARK: - Helpers

    /// Run n fails n % 4 times. The fetch and its two retries make three attempts, so a run
    /// that fails three times gets the fallback.
    private static func failures(ofRun run: Int) -> Int {
        run % 4
    }

    /// A producer that fails a run's first `failures(ofRun:)` calls and succeeds after them. Each
    /// call starts `threadCount` threads that complete it together; every completion call
    /// leaves `completions` when it returns.
    private static func primary(
        countingCallsIn calls: Locked<[Int: Int]>,
        completingFrom threadCount: Int,
        in completions: DispatchGroup
    ) -> DMButtonAction {
        DMButtonAction { completion in
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
            for _ in 0..<threadCount {
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
            for _ in 0..<threadCount {
                gate.signal()
            }
        }
    }

    /// One call per attempt, until a success or the third failure.
    private static func expectedPrimaryCalls(ofRun run: Int) -> Int {
        min(failures(ofRun: run) + 1, 3)
    }

    /// One call after the third failure, none otherwise.
    private static func expectedFallbackCalls(ofRun run: Int) -> Int? {
        failures(ofRun: run) < 3 ? nil : 1
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

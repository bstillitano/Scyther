//
//  HTTPInterceptorURLProtocol.swift
//
//
//  Created by Brandon Stillitano on 22/12/20.
//

import Foundation

/// Property key used to mark requests as internal to prevent infinite logging loops.
internal let internalNetworkRequestKey = "Scyther_Internal_Network_Request"

/// A custom `URLProtocol` subclass that intercepts HTTP/HTTPS requests for logging.
///
/// `HTTPInterceptorURLProtocol` acts as a man-in-the-middle for network requests,
/// capturing request and response data without interfering with normal operation.
/// It stores captured data in `HTTPRequest` objects and adds them to `NetworkLogger`.
///
/// ## How It Works
/// 1. When registered with `URLProtocol.registerClass()`, this class can inspect all URL loading requests
/// 2. It creates a new URLSession to execute the actual request
/// 3. As data arrives, it's forwarded to the original client while being captured for logging
/// 4. Complete request/response data is stored in `HTTPRequest` and logged to `NetworkLogger`
///
/// ## Features
/// - Transparent request/response capture
/// - Authentication challenge handling
/// - HTTP redirect support
/// - Request filtering based on URL patterns
/// - Automatic prevention of infinite logging loops
///
/// - Note: This protocol is automatically registered by `NetworkHelper.start()`.
open class HTTPInterceptorURLProtocol: URLProtocol, @unchecked Sendable {
    /// Guards ``isCancelled``, ``didStartTask``, ``session`` and ``startedTask``.
    ///
    /// Three threads reach that state: `stopLoading()`, on a thread the URL loading system owns;
    /// the block scheduled on ``delayQueue``; and the private session's delegate queue. The
    /// grouping matters more than any single field does — `stopLoading()` has to decide whether a
    /// task exists *and* take hold of it to cancel it as one indivisible act, because a check that
    /// raced the delay block would see `didStartTask == false`, cancel nothing, and let a request
    /// the app had already abandoned go out with nothing left able to stop it.
    private let stateLock = NSLock()

    /// The private session the real data task runs on, or `nil` while no task has been started.
    ///
    /// Built in ``beginTask(with:)`` under ``stateLock`` rather than by a `lazy var`: an
    /// unsynchronised `lazy` initialised from two threads can produce two sessions, and
    /// `stopLoading()` would then invalidate the wrong one.
    private var session: URLSession?

    /// The real data task, once one has been started.
    ///
    /// Recorded in the same critical section that claims the right to start it, so `stopLoading()`
    /// can cancel it directly. Asking the session for its tasks instead delivers the answer on the
    /// session's *delegate queue*, which is the one place a cancellation cannot afford to queue
    /// behind: a paced response occupies that queue, and the cancel would sit behind the pacing
    /// while the socket kept transferring.
    ///
    /// - Note: Only ever read or written under ``stateLock``.
    private var startedTask: URLSessionDataTask?

    private let model: HTTPRequest = .init()
    private var response: URLResponse?
    private var responseData: NSMutableData?

    /// The conditioning a matching rule asked for, stored at `startLoading()` so that
    /// `urlSession(_:dataTask:didReceive:)` can throttle the bytes it forwards.
    ///
    /// - Note: Internal rather than private so a test can drive the delegate callbacks directly
    ///   and measure the pacing. Nothing but `startLoading()` writes it in production.
    internal var condition: NetworkCondition?

    /// The draw that decides whether a condition's ``NetworkCondition/failureRate`` fails this
    /// request. Exactly one draw is made, and only when the rate is strictly between zero and one.
    ///
    /// The range is half-open. A closed `0...1` can return exactly `1`, which the strict
    /// comparison below then lets through — a request escaping a failure rate of `1` once every
    /// 2⁻⁵³ draws.
    ///
    /// - Note: Internal and settable so a test can pin the draw and count it. Nothing in
    ///   production replaces it.
    internal var randomSource: @Sendable () -> Double = { Double.random(in: 0..<1) }

    /// Whether a real data task was started. A stubbed or rule-failed request never creates one,
    /// so `stopLoading()` must not spin up a session just to cancel nothing.
    ///
    /// - Note: Only ever read or written under ``stateLock``.
    private var didStartTask: Bool = false

    /// Set by `stopLoading()` so that neither a pending delayed delivery nor a paced response
    /// part-way through keeps pushing bytes at a client that has gone away.
    ///
    /// - Note: Only ever read or written under ``stateLock``.
    private var isCancelled: Bool = false

    /// Whether `stopLoading()` has been called yet.
    ///
    /// Every caller runs on a thread that does not own this instance — the delay queue, or the
    /// private session's delegate queue — so the read is synchronised with the write in
    /// `stopLoading()`.
    private var hasBeenCancelled: Bool {
        stateLock.withLock { isCancelled }
    }

    /// Whether a real data task has been started.
    ///
    /// - Note: Internal rather than private so a test can assert that a request cancelled while
    ///   its latency was still counting down never reached the network. Nothing in production
    ///   reads it.
    internal var hasStartedTask: Bool {
        stateLock.withLock { didStartTask }
    }

    /// Whether this response is paced to a bandwidth ceiling.
    ///
    /// A request with no ceiling keeps exactly the threading it had before rules existed: its
    /// bytes are forwarded inline, on the delegate queue, as they arrive.
    private var isPaced: Bool {
        (condition?.bandwidthKBps ?? 0) > 0
    }

    /// The queue a paced response is delivered on, private to this request.
    ///
    /// Serial, and the sole owner of every piece of pacing state below — nothing here is touched
    /// from two threads. The wait used to be a `Thread.sleep` on the session's own delegate queue,
    /// which is also where the answer to `getTasksWithCompletionHandler` lands, so a cancellation
    /// could sit behind up to 30 seconds of pacing while the socket kept transferring. Nothing
    /// sleeps now: each chunk is scheduled for the moment the ceiling says its bytes are due, and
    /// no thread is held in the meantime.
    private let deliveryQueue = DispatchQueue(label: "com.scyther.networkRules.delivery",
                                              qos: .userInitiated)

    /// Steps of a paced response waiting to reach the client, oldest first.
    ///
    /// - Note: Only ever touched on ``deliveryQueue``.
    private var pendingSteps: [PacedStep] = []

    /// Whether ``drain()`` is working through ``pendingSteps``, including while it waits for the
    /// next chunk's bytes to fall due. Stops a newly arrived chunk from starting a second pass and
    /// overtaking one that is still pending.
    ///
    /// - Note: Only ever touched on ``deliveryQueue``.
    private var isDraining: Bool = false

    /// Paces the current response part to the ceiling ``condition`` asked for, or `nil` when there
    /// is no ceiling. Rebuilt when a part begins, because the clock is per part.
    ///
    /// - Note: Only ever touched on ``deliveryQueue``.
    private var throttle: BandwidthThrottle?

    /// When the current response part began, which is what the throttle measures against.
    ///
    /// A `DispatchTime` rather than a `Date`: the wall clock can step. Backwards, and the first
    /// chunk appears to owe the entire budget at once; forwards, or across a device wake, and the
    /// ceiling silently stops applying for the rest of the response.
    ///
    /// - Note: Only ever touched on ``deliveryQueue``.
    private var responseStart: DispatchTime = .now()

    /// Seconds of pacing this request has already asked for, across every part of its response.
    ///
    /// - Note: Only ever touched on ``deliveryQueue``.
    private var bandwidthSleepUsed: TimeInterval = 0

    /// Seconds of pacing this request has asked for so far.
    ///
    /// - Note: Internal so a test can assert the budget is spent across the whole request rather
    ///   than reset for each part of it. Nothing in production reads it.
    internal var pacingAsked: TimeInterval {
        deliveryQueue.sync { bandwidthSleepUsed }
    }

    /// The longest a rule may hold a request back before it is sent or answered.
    ///
    /// A developer typing an unreasonable latency into the menu should see a slow request, not a
    /// request that appears to have hung forever.
    private static let maximumDelay: TimeInterval = 30

    /// The longest the bandwidth ceiling may hold this request back, across **every part** of its
    /// response.
    ///
    /// Per request rather than per part, because `multipart/x-mixed-replace` delivers many parts
    /// down one request and a budget that started again with each of them would bound nothing at
    /// all.
    ///
    /// - Note: Internal and settable so a test can shrink it and observe the bound without
    ///   waiting half a minute for it. Nothing in production changes it.
    internal var maximumBandwidthSleep: TimeInterval = 30

    /// One step of a paced response, in the order it has to reach the client.
    ///
    /// Headers, bytes and the terminal callback all travel this queue together, so a response part
    /// can never be announced to the client before the previous part's bytes have been forwarded,
    /// and the load can never be reported finished before its body has been delivered.
    private enum PacedStep {
        /// A response part begins. Restarts the pacing clock, but not the budget.
        case begin(URLResponse)

        /// Bytes to forward once the ceiling says they are due.
        case data(Data)

        /// The load ended; `nil` on success.
        case finish(Error?)
    }

    /// The queue a rule's latency or mock delay is scheduled on.
    ///
    /// `startLoading()` runs on a thread the URL loading system owns, and whether that thread is
    /// per-request or drawn from a shared pool is not ours to know. Sleeping on it to simulate
    /// latency risks holding up traffic that matches no override at all, so the delay is
    /// scheduled here and the load finished from the block. `startLoading()` only has to *start*
    /// the load; the client's callbacks are free to arrive later, on another thread.
    ///
    /// **Concurrent**, and shared by every request in the process. The block a delay schedules is
    /// not merely a wait: serving a stub hands three callbacks to the client and writes the
    /// request and response bodies to the log. On a serial queue one megabyte of mocked JSON
    /// would hold up every other override's delay behind it, so a mock configured for 100 ms
    /// would arrive whenever the queue got round to it.
    private static let delayQueue = DispatchQueue(label: "com.scyther.networkRules.delay",
                                                  qos: .userInitiated,
                                                  attributes: .concurrent)

    override open class func canInit(with request: URLRequest) -> Bool {
        return canServeRequest(request)
    }

    override open class func canInit(with task: URLSessionTask) -> Bool {
        guard let request = task.currentRequest else { return false }
        return canServeRequest(request)
    }

    private class func canServeRequest(_ request: URLRequest) -> Bool {
        /// Check that Scyther has been started and should intercept requests
        guard Scyther.isStarted else {
            return false
        }

        /// Verify that the URL being requested is not a URL that is from our internal  `ScytherProtocol`
        guard URLProtocol.property(forKey: internalNetworkRequestKey, in: request) == nil else {
            return false
        }

        /// Verify that the URL is an `http` and/or `https` URL
        guard let url = request.url, url.absoluteString.hasPrefix("http") || url.absoluteString.hasPrefix("https") else {
            return false
        }

        /// Confirm that the URL is not a URL that should be ignored by the `NetworkHelper` utility class.
        let absoluteString = url.absoluteString
        guard !NetworkHelper.instance.ignoredURLs.contains(where: { absoluteString.hasPrefix($0) }) else {
            return false
        }

        return true
    }

    override open func startLoading() {
        /// Save request to local model
        model.saveRequest(request)

        /// Resolve any rules that apply to this request. The snapshot is lock-guarded because
        /// this method runs on a thread owned by the URL loading system.
        let snapshot = NetworkRuleSnapshot.current
        let outcome = snapshot.isEnabled
            ? NetworkRuleEngine.outcome(for: request, rules: snapshot.rules)
            : .empty
        condition = outcome.condition

        /// Credit only the overrides that shaped the path actually taken. A mock returns before
        /// the rewrite is applied and before the condition is honoured, so listing every matching
        /// override would have the log's Overrides row naming ones that did nothing.
        if let stub = outcome.stub, let url = request.url {
            let bodies = { NetworkRuleStore.bodyDataOffMainActor(for: $0) }
            if let (response, body) = NetworkRuleStubResponder.response(for: stub, url: url, bodyProvider: bodies) {
                /// Names and ids are parallel: same length, same order, one entry per override
                /// credited. The details page looks the override up by id and shows the name, so
                /// the two are always assigned together and must never be allowed to drift.
                model.appliedRuleNames = outcome.stubRuleName.map { [$0] } ?? []
                model.appliedRuleIDs = outcome.stubRuleID.map { [$0] } ?? []
                let delay = min(NetworkRuleStubResponder.delay(for: stub), Self.maximumDelay)
                perform(after: delay) { $0.serve(response, body: body) }
                return
            }
        }

        /// Either nothing stubbed this request or the stub could not be produced — a map-local
        /// file that has been deleted, say — so it goes to the network and the rules that shape
        /// it there are the ones to credit.
        /// Parallel to ``HTTPRequest/appliedRuleNames``, as on the stub path above: same length,
        /// same order, assigned together.
        model.appliedRuleNames = outcome.networkRuleNames
        model.appliedRuleIDs = outcome.networkRuleIDs

        /// Continue executing request
        guard let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            return
        }

        /// Apply any header rewrite, then re-capture the request so the log describes what actually
        /// goes on the wire. Without the second `saveRequest` a developer checking whether their
        /// rewrite rule worked would see the pre-rewrite headers and cURL and conclude it had not.
        if let rewrite = outcome.headerRewrite {
            rewrite.apply(to: mutableRequest)
            model.saveRequest(mutableRequest as URLRequest)
        }

        URLProtocol.setProperty(true, forKey: internalNetworkRequestKey, in: mutableRequest)

        /// The latency comes first and the failure is rolled after it. Rolling first would fail a
        /// "slow and flaky" condition at t = 0, which is not how a degraded link behaves: a
        /// request that is going to time out still waits before it does.
        let outgoing = mutableRequest as URLRequest
        let condition = outcome.condition
        let latency = min(condition?.latency ?? 0, Self.maximumDelay)
        perform(after: latency) { interceptor in
            if let condition, interceptor.shouldFail(condition) {
                interceptor.failRequest(with: condition)
                return
            }
            interceptor.beginTask(with: outgoing)
        }
    }

    /// Whether this request is the one a condition's failure rate takes out.
    ///
    /// A rate of one or more fails and a rate of zero or less proceeds without drawing at all, so
    /// neither depends on the exact bounds of ``randomSource``'s range. Anything between the two
    /// draws exactly once, per request rather than per chunk or per matching rule, and compares
    /// strictly — a draw equal to the rate proceeds.
    ///
    /// - Parameter condition: The condition that matched this request.
    /// - Returns: `true` when the request should be failed rather than sent.
    private func shouldFail(_ condition: NetworkCondition) -> Bool {
        guard condition.failureRate > 0 else { return false }
        guard condition.failureRate < 1 else { return true }
        return randomSource() < condition.failureRate
    }

    /// Fails this request with the error `condition` asked for, and records the attempt.
    ///
    /// - Parameter condition: The condition that took the request out.
    private func failRequest(with condition: NetworkCondition) {
        model.saveErrorResponse()
        finishWithFailure(URLError(URLError.Code(rawValue: condition.failureCode)))
    }

    /// Finishes starting the load, after a rule's delay if it asked for one.
    ///
    /// A delay of zero runs `work` inline, so a request no condition or mock delay touches keeps
    /// exactly the threading and ordering it had before rules existed. Anything above zero is
    /// scheduled on ``delayQueue`` instead of slept for — see that queue's note.
    ///
    /// - Parameters:
    ///   - delay: Seconds to wait, already clamped to ``maximumDelay``.
    ///   - work: What to do once the wait is over. Skipped entirely when the request has been
    ///     cancelled in the meantime, so a cancelled request delivers nothing, and when the
    ///     instance is gone.
    private func perform(after delay: TimeInterval, _ work: @escaping @Sendable (HTTPInterceptorURLProtocol) -> Void) {
        guard delay > 0 else {
            work(self)
            return
        }
        Self.delayQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.hasBeenCancelled else { return }
            work(self)
        }
    }

    /// Starts the real data task, unless `stopLoading()` got there first.
    ///
    /// Takes ``stateLock`` once and performs, indivisibly, the four things `stopLoading()` must
    /// never catch half-done: it refuses a request that has already been cancelled, records that a
    /// task now exists, creates the session that task belongs to, and creates and records the task
    /// itself. Recording the task under the same lock is what closes the window a cancel used to
    /// fall into — the task was created and resumed by the caller after the lock was released, so
    /// a `stopLoading()` landing in between saw `didStartTask == true`, found no task on the
    /// session to cancel, and let a request the app had already abandoned go out with nothing left
    /// able to stop it.
    ///
    /// Only `resume()` happens outside the lock, because it reaches into `URLSession`, and the
    /// state is re-read straight afterwards so that a cancel arriving in that last sliver still
    /// reaches the task.
    ///
    /// - Parameter request: The request to send.
    private func beginTask(with request: URLRequest) {
        stateLock.lock()
        guard !isCancelled else {
            stateLock.unlock()
            return
        }
        didStartTask = true
        let session = self.session ?? URLSession(configuration: .default,
                                                 delegate: self,
                                                 delegateQueue: nil)
        self.session = session
        let task = session.dataTask(with: request)
        startedTask = task
        stateLock.unlock()

        task.resume()

        guard hasBeenCancelled else { return }
        task.cancel()
        session.invalidateAndCancel()
    }

    /// Hands a rule's synthesised response to the client as though it had come from the network.
    ///
    /// No data task is created, so a mocked request never leaves the device. The response is
    /// logged exactly as a real one is, with ``HTTPRequest/wasStubbed`` set so the log can say
    /// where it came from.
    ///
    /// Any delay the mock asked for has already elapsed by the time this is called — see
    /// ``perform(after:_:)`` — so this never waits.
    ///
    /// Cancellation is re-checked before every callback rather than only once on the way in. A
    /// `stopLoading()` can land between them — the client is entitled to cancel from inside the
    /// response callback — and delivering to a client that has been told to stop is something the
    /// `URLProtocol` contract forbids. Nothing is logged either: a response the client never
    /// received is not one the log should claim was served.
    ///
    /// - Parameters:
    ///   - response: The response to serve.
    ///   - body: The response body.
    private func serve(_ response: HTTPURLResponse, body: Data) {
        guard !hasBeenCancelled else { return }
        client?.urlProtocol(self,
                            didReceive: response,
                            cacheStoragePolicy: NetworkHelper.instance.cacheStoragePolicy)

        guard !hasBeenCancelled else { return }
        client?.urlProtocol(self, didLoad: body)

        guard !hasBeenCancelled else { return }
        client?.urlProtocolDidFinishLoading(self)

        model.saveRequestBody(request)
        model.logRequest(request)
        model.wasStubbed = true
        model.saveResponse(response, data: body)

        let capturedModel = model
        Task { @MainActor in
            await NetworkLogger.instance.add(capturedModel)
            NotificationCenter.default.post(name: .LoggerReloadData, object: nil)
        }
    }

    /// Fails the request with the error a condition rule asked for, and logs the attempt.
    ///
    /// - Parameter error: The error to surface to the caller.
    private func finishWithFailure(_ error: URLError) {
        client?.urlProtocol(self, didFailWithError: error)

        model.saveRequestBody(request)
        model.logRequest(request)

        let capturedModel = model
        Task { @MainActor in
            await NetworkLogger.instance.add(capturedModel)
            NotificationCenter.default.post(name: .LoggerReloadData, object: nil)
        }
    }

    /// Marks the request cancelled and cancels the data task, if one ever started.
    ///
    /// The flag and the task are read together under ``stateLock`` so that a delay block running
    /// concurrently either starts its task before this reads the state — in which case the task is
    /// here to cancel — or finds the request already cancelled and starts nothing. The
    /// cancellation itself happens after the lock is released, because it calls into `URLSession`.
    ///
    /// The task is cancelled **directly**. Asking the session for its tasks instead delivers the
    /// answer on the session's delegate queue, which is the same queue a paced response runs on:
    /// `stopLoading()` would return, the app would believe the request cancelled, and the
    /// cancellation would sit behind the pacing — up to 30 seconds — while the socket carried on
    /// transferring.
    ///
    /// Invalidating is what releases the session's strong reference to this instance as its
    /// delegate. Without it every intercepted request leaked the protocol instance, the session,
    /// its operation queue, the logged ``HTTPRequest`` and the whole response body.
    override open func stopLoading() {
        stateLock.lock()
        isCancelled = true
        let task = startedTask
        let session = self.session
        stateLock.unlock()

        task?.cancel()
        session?.invalidateAndCancel()
    }

    override open class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
}

extension HTTPInterceptorURLProtocol: URLSessionDataDelegate {
    /// Forwards received bytes to the client, honouring any bandwidth ceiling a condition rule set.
    ///
    /// Without a ceiling the bytes go straight to the client on this thread, exactly as they did
    /// before rules existed. With one, they are handed to ``deliveryQueue`` and this returns at
    /// once: the wait is scheduled, not slept for, so the session's delegate queue stays free and
    /// a `stopLoading()` can never queue behind the pacing.
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        responseData?.append(data)

        guard isPaced else {
            client?.urlProtocol(self, didLoad: data)
            return
        }
        enqueue(.data(data))
    }

    /// Announces a response — or the next part of one — to the client.
    ///
    /// A paced response announces its parts through ``deliveryQueue`` alongside its bytes, so that
    /// a second part of a `multipart/x-mixed-replace` response cannot be announced while the first
    /// part's body is still being forwarded. The disposition is answered here regardless, because
    /// the session waits on it before delivering anything more.
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.response = response
        responseData = NSMutableData()

        if isPaced {
            enqueue(.begin(response))
        } else {
            client?.urlProtocol(self,
                                didReceive: response,
                                cacheStoragePolicy: NetworkHelper.instance.cacheStoragePolicy)
        }
        completionHandler(.allow)
    }

    /// Hands one step of a paced response to the delivery pump.
    ///
    /// - Parameter step: The step to append. Steps are delivered in the order they are enqueued.
    private func enqueue(_ step: PacedStep) {
        deliveryQueue.async { [weak self] in
            guard let self else { return }
            self.pendingSteps.append(step)
            guard !self.isDraining else { return }
            self.isDraining = true
            self.drain()
        }
    }

    /// Delivers every step the ceiling allows right now, then schedules itself to resume when the
    /// next chunk's bytes fall due.
    ///
    /// Always runs on ``deliveryQueue``. It loops rather than recursing, because a response
    /// comfortably under its ceiling never waits at all and would otherwise recurse once per
    /// chunk. Cancellation is re-checked on every pass and drops whatever is left, so a client
    /// that has gone away is never handed more bytes.
    private func drain() {
        while true {
            if hasBeenCancelled {
                pendingSteps.removeAll()
                isDraining = false
                return
            }
            guard !pendingSteps.isEmpty else {
                isDraining = false
                return
            }

            switch pendingSteps.removeFirst() {
            case .begin(let response):
                /// A new part restarts the clock but not the budget — see
                /// ``maximumBandwidthSleep``.
                responseStart = .now()
                throttle = BandwidthThrottle(
                    bandwidthKBps: condition?.bandwidthKBps,
                    maximumTotalSleep: max(0, maximumBandwidthSleep - bandwidthSleepUsed)
                )
                client?.urlProtocol(self,
                                    didReceive: response,
                                    cacheStoragePolicy: NetworkHelper.instance.cacheStoragePolicy)

            case .data(let data):
                let wait = throttle?.delay(forwarding: data.count, elapsed: elapsedInPart) ?? 0
                guard wait > 0 else {
                    client?.urlProtocol(self, didLoad: data)
                    continue
                }
                bandwidthSleepUsed += wait
                deliveryQueue.asyncAfter(deadline: .now() + wait) { [weak self] in
                    guard let self else { return }
                    if !self.hasBeenCancelled {
                        self.client?.urlProtocol(self, didLoad: data)
                    }
                    self.drain()
                }
                return

            case .finish(let error):
                deliverTerminal(error)
                stateLock.withLock { session }?.finishTasksAndInvalidate()
                isDraining = false
                return
            }
        }
    }

    /// Seconds since the current response part began, on a clock that cannot step.
    ///
    /// - Note: Only ever read on ``deliveryQueue``.
    private var elapsedInPart: TimeInterval {
        let now = DispatchTime.now().uptimeNanoseconds
        let start = responseStart.uptimeNanoseconds
        guard now > start else { return 0 }
        return Double(now - start) / 1_000_000_000
    }

    /// Tells the client how the load ended.
    ///
    /// - Parameter error: The failure, or `nil` when the load succeeded.
    private func deliverTerminal(_ error: Error?) {
        if let error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    /// Finishes the load, logs it, and invalidates the private session.
    ///
    /// The invalidation is the point at which the session releases its strong reference to this
    /// instance as its delegate. Skipping it leaked, per intercepted request, the protocol
    /// instance, the session, its operation queue, the logged ``HTTPRequest`` and an
    /// `NSMutableData` holding the entire response body. It goes last, after the client has been
    /// told how the load ended, and `finishTasksAndInvalidate()` rather than
    /// `invalidateAndCancel()` so that a callback still in flight on the delegate queue is allowed
    /// to finish.
    ///
    /// A paced response reports both through ``deliveryQueue`` instead. The task finishes as soon
    /// as the last bytes are off the socket, which is well before the ceiling has finished handing
    /// them to the client, and telling the client the load had finished at that point would have
    /// it believe a body it had not yet received was complete.
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        defer {
            if isPaced {
                enqueue(.finish(error))
            } else {
                deliverTerminal(error)
                session.finishTasksAndInvalidate()
            }
        }

        guard let request = task.originalRequest else {
            NotificationCenter.default.post(name: .LoggerReloadData, object: nil)
            return
        }

        model.saveRequestBody(request)
        model.logRequest(request)

        if error != nil {
            model.saveErrorResponse()
        } else if let response = response {
            let data = (responseData ?? NSMutableData()) as Data
            model.saveResponse(response, data: data)
        }

        let capturedModel = model
        Task { @MainActor in
            await NetworkLogger.instance.add(capturedModel)
            NotificationCenter.default.post(name: .LoggerReloadData, object: nil)
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let updatedRequest: URLRequest
        if URLProtocol.property(forKey: internalNetworkRequestKey, in: request) != nil {
            let mutableRequest = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
            URLProtocol.removeProperty(forKey: internalNetworkRequestKey, in: mutableRequest)

            updatedRequest = mutableRequest as URLRequest
        } else {
            updatedRequest = request
        }

        client?.urlProtocol(self, wasRedirectedTo: updatedRequest, redirectResponse: response)
        completionHandler(updatedRequest)
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let wrappedChallenge = URLAuthenticationChallenge(authenticationChallenge: challenge, sender: LoggerAuthenticationChallengeSender(handler: completionHandler))
        client?.urlProtocol(self, didReceive: wrappedChallenge)
    }

    #if !os(OSX)
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        client?.urlProtocolDidFinishLoading(self)
    }
    #endif
}

//
//  HTTPInterceptorURLProtocol.swift
//
//
//  Created by Brandon Stillitano on 22/12/20.
//

import Foundation

/// Property key used to mark requests as internal to prevent infinite logging loops.
internal let internalNetworkRequestKey = "Scyther_Internal_Network_Request"

/// Property key carrying the hash of the request a replay was built from.
///
/// Set by ``ReplayableRequest/makeURLRequest(replayOf:)`` and read back in
/// ``HTTPRequest/saveRequest(_:)``, which is how a replay is told apart from traffic the app
/// actually made. It is stripped on redirect, alongside ``internalNetworkRequestKey``: the entry
/// a redirect produces is a request in its own right, not a second replay of the original.
internal let replayOfRequestKey = "Scyther_Replay_Of_Request"

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
/// - Scyther's own requests logged but exempt from every interception feature, so the toolkit
///   never instruments itself — see ``ScytherOriginatedRequest``
///
/// - Note: This protocol is automatically registered by `NetworkHelper.start()`.
open class HTTPInterceptorURLProtocol: URLProtocol, @unchecked Sendable {
    /// Guards ``isCancelled``, ``didStartTask``, ``session``, ``startedTask``,
    /// ``pendingBreakpointID``, ``holdCount`` and ``resolvedHold``.
    ///
    /// Four threads reach that state: `stopLoading()`, on a thread the URL loading system owns;
    /// the block scheduled on ``delayQueue``; the coordinator's queue, when a held exchange is
    /// let go; and the private session's delegate queue. The grouping matters more than any single
    /// field does — `stopLoading()` has to observe the cancellation *and* take hold of everything
    /// there is to cancel, the data task and the pause alike, as one indivisible act, because a
    /// check that raced ``beginTask(with:)`` would find no task recorded, cancel nothing, and let
    /// a request the app had already abandoned go out with nothing left able to stop it.
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

    /// Where a held request or response waits for the developer's decision.
    ///
    /// - Note: Internal and settable so a test can drive a breakpoint on a coordinator of its own
    ///   rather than the shared one. Nothing in production replaces it.
    internal var breakpoints: BreakpointCoordinator = .shared

    /// The breakpoint holding this request's *response*, stored at `startLoading()` so the
    /// delegate callbacks know to withhold what they would otherwise forward.
    ///
    /// Written once, before any task exists, and read afterwards on the session's delegate queue —
    /// the same arrangement ``condition`` has.
    ///
    /// - Note: Internal rather than private so a test can drive the delegate callbacks directly.
    ///   Nothing but `startLoading()` writes it in production.
    internal var heldBreakpoint: NetworkBreakpoint?

    /// The identifier of the pause this exchange is held at, or `nil` when nothing is held.
    ///
    /// - Note: Only ever read or written under ``stateLock``, because `stopLoading()` has to take
    ///   hold of it to cancel the pause.
    private var pendingBreakpointID: UUID?

    /// How many exchanges this request has held so far, which is what identifies a hold to
    /// ``recordPendingBreakpoint(_:for:)``.
    ///
    /// At most two: the request, then its response.
    ///
    /// - Note: Only ever read or written under ``stateLock``.
    private var holdCount: Int = 0

    /// The token of the most recent hold whose continuation has already run, or zero while none
    /// has.
    ///
    /// - Note: Only ever read or written under ``stateLock``.
    private var resolvedHold: Int = 0

    /// The largest response a breakpoint will hold, in bytes.
    ///
    /// This bounds how long a large body is **held**, not the memory it takes. Every byte is
    /// buffered into ``responseData`` on the way through whether or not a breakpoint matched —
    /// that is what the log is written from — so a response over the cap has already been
    /// accumulated by the time it is measured here. What the cap buys is that a download nobody
    /// is going to read in an editor is forwarded on as it stands, rather than sitting in the app
    /// for up to ``NetworkBreakpoint/timeoutRange``'s upper bound while an editor offers a body
    /// no one wants. The skip is logged.
    ///
    /// - Note: Internal and settable so a test can shrink it rather than allocate ten megabytes.
    ///   Nothing in production changes it.
    internal var maximumHeldResponseBytes: Int = 10 * 1024 * 1024

    /// Overrides the timeout a matching breakpoint asks for.
    ///
    /// - Note: Internal and settable so a test can hold an exchange for a fraction of a second
    ///   rather than the five seconds ``NetworkBreakpoint/timeoutRange`` sets as its floor.
    ///   Nothing in production sets it.
    internal var breakpointTimeoutOverride: TimeInterval?

    /// Whether a real data task was started. A stubbed or rule-failed request never creates one.
    ///
    /// Nothing in production reads it: `stopLoading()` cancels ``startedTask`` directly, and a
    /// request that started no task simply has none recorded to cancel. It is kept because it is
    /// the only way a test can ask whether a request reached the network at all — see
    /// ``hasStartedTask`` — for which asking the session would be both asynchronous and, once the
    /// session has been invalidated, too late.
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

    /// Whether this exchange is one Scyther itself started, and so is exempt from every
    /// interception feature while still being logged.
    ///
    /// Computed rather than stored, because the answer lives on the immutable `request` this
    /// instance was created with and is therefore the same on every thread that asks — no lock,
    /// no initialisation order to get wrong, and no chance of a stored copy drifting from the
    /// request it describes. See ``ScytherOriginatedRequest`` for what the mark is and why it is
    /// not a header.
    internal var isScytherOriginated: Bool {
        ScytherOriginatedRequest.identifies(request)
    }

    /// Whether this response is paced to a bandwidth ceiling.
    ///
    /// A request with no ceiling keeps exactly the threading it had before rules existed: its
    /// bytes are forwarded inline, on the delegate queue, as they arrive.
    private var isPaced: Bool {
        (condition?.bandwidthKBps ?? 0) > 0
    }

    /// The queue this request's own callbacks are delivered on, private to it.
    ///
    /// Serial, and the sole owner of every piece of pacing state below — nothing here is touched
    /// from two threads. The wait used to be a `Thread.sleep` on the session's own delegate queue,
    /// which is also where the answer to `getTasksWithCompletionHandler` lands, so a cancellation
    /// could sit behind up to 30 seconds of pacing while the socket kept transferring. Nothing
    /// sleeps now: each chunk is scheduled for the moment the ceiling says its bytes are due, and
    /// no thread is held in the meantime.
    ///
    /// A breakpoint's continuation lands here too, for the mirror reason. It arrives on
    /// ``BreakpointCoordinator``'s serial queue, which every live pause in the process shares, and
    /// what it goes on to do — start a task, hand a response to the client, write both bodies to
    /// the log — is neither quick nor bounded. Because this queue belongs to one request, nothing
    /// but this request ever waits behind that work.
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

    /// The stubbed response waiting to be written to the log once its paced bytes have all
    /// reached the client, or `nil` when nothing stubbed this request.
    ///
    /// An unpaced stub is logged inline, the moment it has been delivered. A paced one is
    /// delivered over time and its log entry has to wait for the last chunk, so it is parked here
    /// and written by ``drain()``. Cleared without being written when the request is cancelled
    /// part-way through, because a response the client never received is not one the log should
    /// claim was served.
    ///
    /// - Note: Only ever touched on ``deliveryQueue``.
    private var pendingStubLog: (response: HTTPURLResponse, body: Data)?

    /// The size of one paced piece of a stubbed body, in bytes.
    ///
    /// Chosen to sit in the same range as the chunks `URLSession` hands its delegate, so a
    /// synthetic body is paced with roughly the granularity a real one is.
    private static let stubChunkSize = 8 * 1024

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

        /// Verify the URL is one Scyther intercepts at all.
        guard let url = request.url, isInterceptable(url) else {
            return false
        }

        return true
    }

    /// Whether a URL is one Scyther intercepts: an HTTP URL that the host app has not asked it to
    /// leave alone.
    ///
    /// Split out of ``canInit(with:)-(URLRequest)`` so the replay editor can ask the same question
    /// before it sends. A replay retargeted at an ignored host, or at a scheme that is not HTTP,
    /// goes out perfectly well and is never captured — so without this the editor promised in a
    /// footer that replays are logged like app traffic and then produced no log entry, no error
    /// and no explanation.
    ///
    /// The two conditions this leaves out of ``canServeRequest(_:)`` are about the process rather
    /// than the URL: whether Scyther has started, and whether the request is Scyther's own.
    ///
    /// - Parameter url: The URL to test.
    /// - Returns: Whether the interceptor would capture a request sent to it.
    static func isInterceptable(_ url: URL) -> Bool {
        let absoluteString = url.absoluteString
        guard absoluteString.hasPrefix("http") else { return false }
        return !NetworkHelper.instance.ignoredURLs.contains(where: { absoluteString.hasPrefix($0) })
    }

    override open func startLoading() {
        /// Save request to local model
        model.saveRequest(request)

        /// Resolve any rules that apply to this request. The snapshot is lock-guarded because
        /// this method runs on a thread owned by the URL loading system.
        ///
        /// Scyther's own traffic resolves to nothing at all — see ``isScytherOriginated`` — so it
        /// is never stubbed and never rewritten, while still reaching ``model`` and therefore the
        /// log.
        let snapshot = NetworkRuleSnapshot.current
        let outcome = (snapshot.isEnabled && !isScytherOriginated)
            ? NetworkRuleEngine.outcome(for: request, rules: snapshot.rules)
            : .empty

        /// Global conditioning is a floor, not an addition: a matching override's own condition
        /// replaces it outright, so conditioning one endpoint still beats whatever the whole app
        /// is set to. Adding the two would make a targeted "fast path" impossible to express.
        ///
        /// The floor stops at Scyther's own requests. A developer who has switched the whole app
        /// to a lossy 2G link has not asked for the menu's own IP lookup to fail with it.
        let condition = isScytherOriginated ? nil : (outcome.condition ?? snapshot.globalCondition)
        self.condition = condition

        /// The global condition is credited on the request it shapes, exactly as an override's
        /// own condition is. It has no rule behind it, so it is credited by name with no
        /// identifier, and the log's brown `OVERRIDDEN` badge — which reads the credits — is
        /// finally true of a globally conditioned request. Without it a request the developer had
        /// deliberately slowed or failed was indistinguishable in the list from ordinary traffic,
        /// which is the one thing that badge exists to prevent.
        let isGloballyConditioned = outcome.condition == nil && (condition?.shapesTheRequest ?? false)

        guard let stub = outcome.stub, let url = request.url else {
            beginNetworkPath(outcome: outcome, condition: condition, creditingGlobalCondition: isGloballyConditioned)
            return
        }

        /// A stub short-circuits the network, but no longer suppresses the other two actions. The
        /// condition applies to the synthesised response — it delays, paces and can fail it — and
        /// the rewrite is applied to the request the *log* describes, so the log shows what would
        /// have gone out even though nothing does. Both are credited accordingly.
        ///
        /// The stub's own delay and the condition's latency are both "wait before this answers",
        /// so they add rather than one silently winning — then the pair is clamped once, so two
        /// reasonable numbers cannot combine into an apparent hang.
        let delay = min(stub.delay + (condition?.latency ?? 0), Self.maximumDelay)

        /// Producing the stub reads a mock body or a mapped file off disk, and neither read is
        /// bounded — a mock body is whatever the developer stored and a mapped file is whatever is
        /// on the device. Both are taken on ``delayQueue`` rather than on the thread the URL
        /// loading system gave us, for the same reason the delay itself is scheduled rather than
        /// slept for: that thread may be shared with traffic matching no override at all. A stub
        /// that cannot be produced falls through to the network from there too, so neither branch
        /// of the decision touches disk on the caller's thread.
        Self.delayQueue.async { [weak self] in
            guard let self, !self.hasBeenCancelled else { return }
            self.serveStub(stub,
                           url: url,
                           outcome: outcome,
                           condition: condition,
                           delay: delay,
                           creditingGlobalCondition: isGloballyConditioned)
        }
    }

    /// Produces the stub an override asked for and serves it, or falls through to the network.
    ///
    /// - Parameters:
    ///   - stub: The mock or map-local action that matched.
    ///   - url: The request's URL, which the synthesised response is built against.
    ///   - outcome: Everything the rules resolved to, for the credits and the rewrite.
    ///   - condition: The conditioning that applies to the synthesised response, if any.
    ///   - delay: Seconds to wait before answering, already clamped to ``maximumDelay``.
    ///   - creditingGlobalCondition: Whether the conditioning came from the global floor rather
    ///     than from an override, and so is credited by name with no identifier.
    /// - Note: Only ever called on ``delayQueue``, because it reads a body off disk.
    private func serveStub(_ stub: NetworkRuleStub,
                           url: URL,
                           outcome: NetworkRuleOutcome,
                           condition: NetworkCondition?,
                           delay: TimeInterval,
                           creditingGlobalCondition: Bool) {
        let bodies = { NetworkRuleStore.bodyDataOffMainActor(for: $0) }
        guard let (response, body) = NetworkRuleStubResponder.response(for: stub, url: url, bodyProvider: bodies) else {
            beginNetworkPath(outcome: outcome,
                             condition: condition,
                             creditingGlobalCondition: creditingGlobalCondition)
            return
        }

        /// Names and ids are parallel: same length, same order, one entry per override credited.
        /// The details page looks the override up by id and shows the name, so the two are always
        /// assigned together and must never be allowed to drift.
        let credits = outcome.stubbedCredits
        model.appliedRuleNames = credits.names
        model.appliedRuleIDs = credits.ids.map { $0 }
        creditGlobalCondition(if: creditingGlobalCondition)
        _ = rewrittenRequest(applying: outcome.headerRewrite)

        perform(after: delay) { interceptor in
            if let condition, interceptor.shouldFail(condition) {
                interceptor.failRequest(with: condition)
                return
            }
            interceptor.serve(response, body: body)
        }
    }

    /// Sends the request to the network, through any rewrite and any breakpoint that matched it.
    ///
    /// Reached either because nothing stubbed this request or because the stub could not be
    /// produced — a map-local file that has been deleted, say. The stub is not credited in either
    /// case, because it served nothing; everything else that matched is.
    ///
    /// - Parameters:
    ///   - outcome: Everything the rules resolved to, for the credits and the rewrite.
    ///   - condition: The conditioning that applies to the request, if any.
    ///   - creditingGlobalCondition: Whether the conditioning came from the global floor rather
    ///     than from an override, and so is credited by name with no identifier.
    /// - Note: Runs on the thread `startLoading()` was called on when nothing stubbed the request,
    ///   which is what keeps an unmatched request's threading exactly as it was before rules
    ///   existed; and on ``delayQueue`` when a stub matched but could not be produced.
    /// Adds the global conditioning to this request's credits, when it is what shaped it.
    ///
    /// Appended after the overrides' own credits, so the names read in the order they applied:
    /// an override matched but conditioned nothing, and the global floor did the conditioning.
    /// The identifier is `nil` because there is no override to open — the global condition is a
    /// screen, not a rule — which is what ``HTTPRequest/appliedRuleIDs``' optional element is for.
    ///
    /// - Parameter isCredited: Whether the conditioning came from the global floor.
    private func creditGlobalCondition(if isCredited: Bool) {
        guard isCredited else { return }
        model.appliedRuleNames.append(localized("Network Conditioning"))
        model.appliedRuleIDs.append(nil)
    }

    private func beginNetworkPath(outcome: NetworkRuleOutcome,
                                  condition: NetworkCondition?,
                                  creditingGlobalCondition: Bool) {
        /// Names and ids stay parallel, as on the stubbed path: same length, same order, assigned
        /// together.
        model.appliedRuleNames = outcome.networkRuleNames
        model.appliedRuleIDs = outcome.networkRuleIDs.map { $0 }
        creditGlobalCondition(if: creditingGlobalCondition)

        /// Continue executing request
        guard let mutableRequest = rewrittenRequest(applying: outcome.headerRewrite) else {
            return
        }

        URLProtocol.setProperty(true, forKey: internalNetworkRequestKey, in: mutableRequest)

        /// `mutableCopy()` carries protocol properties across, so the marker is already here —
        /// but re-stamping it costs a dictionary write and removes the whole question from the
        /// list of things a future change to ``rewrittenRequest(applying:)`` could quietly break.
        /// The cost of losing the marker is the toolkit instrumenting itself again.
        if isScytherOriginated {
            ScytherOriginatedRequest.mark(mutableRequest)
        }

        let outgoing = mutableRequest as URLRequest
        let latency = min(condition?.latency ?? 0, Self.maximumDelay)

        /// Read once, so the request stage and the response stage cannot disagree about what is
        /// configured because the developer edited a breakpoint in between. A stubbed request
        /// never reaches here: a stub answers the request itself, so there is nothing in flight
        /// for a breakpoint to hold.
        ///
        /// Scyther's own requests are never held, at either stage. Holding the menu's IP lookup
        /// paused the very menu the developer would have used to switch the breakpoint off, and
        /// presenting the editor over the menu re-ran the lookup, which was held in turn — one
        /// modal per second, without limit.
        let breakpointState = isScytherOriginated ? .empty : BreakpointSnapshot.current
        heldBreakpoint = breakpointState.breakpoint(matching: outgoing, stage: .response)

        if let held = breakpointState.breakpoint(matching: outgoing, stage: .request) {
            hold(outgoing, at: held, condition: condition, latency: latency)
            return
        }

        startNetworkLoad(with: outgoing, condition: condition, latency: latency)
    }

    /// Holds the outgoing request at a breakpoint and **returns**, having handed the coordinator
    /// the continuation that resumes it.
    ///
    /// Nothing waits here. `startLoading()` runs on a thread the URL loading system owns, and the
    /// request is in flight as far as that system is concerned; the continuation runs later, on
    /// the coordinator's own queue, and hands the work to ``deliveryQueue`` from there.
    ///
    /// That hop is not a detail. The coordinator's queue is serial and shared by every live pause
    /// in the process, and resuming an exchange writes bodies to the log — so doing the work on it
    /// would put this request's disk I/O in front of another pause's registration, cancellation
    /// and timeout. ``deliveryQueue`` is private to this request, so nothing else waits on it.
    ///
    /// The continuation captures `self` strongly, which is deliberate: while an exchange is held,
    /// the pause is what owns it. Every path out of the pause — a decision, the timeout, a
    /// cancellation — drops the continuation, so the hold is bounded by
    /// ``NetworkBreakpoint/timeoutRange``'s upper bound at worst.
    ///
    /// - Parameters:
    ///   - request: The request as it would have been sent.
    ///   - breakpoint: The breakpoint that matched.
    ///   - condition: The conditioning to apply once the request is let go, if any.
    ///   - latency: The latency to apply once the request is let go.
    private func hold(_ request: URLRequest,
                      at breakpoint: NetworkBreakpoint,
                      condition: NetworkCondition?,
                      latency: TimeInterval) {
        let draft = BreakpointDraft(request: request)
        model.breakpointNames.append(breakpoint.name)

        let token = beginHold()
        let id = breakpoints.pause(draft,
                                   name: breakpoint.name,
                                   stage: .request,
                                   timeout: breakpointTimeoutOverride ?? breakpoint.timeout) { [self] resolution in
            endHold(token)

            deliveryQueue.async { [self] in
                /// A client that has gone away is handed nothing at all, which is what the
                /// `URLProtocol` contract requires. The coordinator drops a cancelled pause before
                /// it gets here; this covers a cancellation that lands while the decision is in
                /// flight, or while it is queued behind this hop.
                guard !hasBeenCancelled else { return }

                switch resolution {
                case .continue(let edited):
                    model.wasEdited = model.wasEdited || edited != draft
                    let rebuilt = Self.marked(edited.makeURLRequest(basedOn: request))

                    /// The log has to describe the request as actually sent, exactly as it does
                    /// for a header rewrite — otherwise a developer checking whether their edit
                    /// went out would see the request they edited away from.
                    model.saveRequest(rebuilt)
                    startNetworkLoad(with: rebuilt, condition: condition, latency: latency)

                case .timedOut:
                    startNetworkLoad(with: request, condition: condition, latency: latency)

                case .abort(let code):
                    model.saveErrorResponse()
                    finishWithFailure(URLError(code))
                }
            }
        }

        recordPendingBreakpoint(id, for: token)
    }

    /// Starts the load, after a condition's latency and its failure roll.
    ///
    /// The latency comes first and the failure is rolled after it. Rolling first would fail a
    /// "slow and flaky" condition at t = 0, which is not how a degraded link behaves: a request
    /// that is going to time out still waits before it does.
    ///
    /// - Parameters:
    ///   - request: The request to send.
    ///   - condition: The conditioning that applies to it, if any.
    ///   - latency: Seconds to wait first, already clamped to ``maximumDelay``.
    private func startNetworkLoad(with request: URLRequest,
                                  condition: NetworkCondition?,
                                  latency: TimeInterval) {
        perform(after: latency) { interceptor in
            if let condition, interceptor.shouldFail(condition) {
                interceptor.failRequest(with: condition)
                return
            }
            interceptor.beginTask(with: request)
        }
    }

    /// The request with the marker that stops the interceptor picking it up a second time.
    ///
    /// A request rebuilt from an edited draft keeps the original's protocol properties, so this is
    /// belt and braces — but the cost of losing that marker is a request that intercepts itself
    /// forever, which is not a failure mode worth leaving to an implementation detail of
    /// `NSURLRequest` copying.
    ///
    /// - Note: Internal rather than private so a test can assert the marker survives an edit that
    ///   changes the URL.
    ///
    /// - Parameter request: The request about to be sent.
    /// - Returns: The same request, marked.
    internal static func marked(_ request: URLRequest) -> URLRequest {
        guard let mutable = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            return request
        }
        URLProtocol.setProperty(true, forKey: internalNetworkRequestKey, in: mutable)
        return mutable as URLRequest
    }

    /// Claims a token for an exchange about to be held.
    ///
    /// Taken *before* the pause is registered, so that a decision arriving immediately afterwards
    /// can be matched to a hold this thread has not finished setting up yet.
    ///
    /// - Returns: The hold's token.
    private func beginHold() -> Int {
        stateLock.withLock {
            holdCount += 1
            return holdCount
        }
    }

    /// Marks a hold resolved and forgets the pause it was registered under.
    ///
    /// - Parameter token: The token ``beginHold()`` gave this hold.
    private func endHold(_ token: Int) {
        stateLock.withLock {
            resolvedHold = max(resolvedHold, token)
            pendingBreakpointID = nil
        }
    }

    /// Remembers the pause this exchange is held at, so `stopLoading()` can cancel it.
    ///
    /// The cancellation flag and the hold's own token are read in the same critical section that
    /// records the identifier, because both can be settled before this runs.
    /// A `stopLoading()` that landed while the pause was being registered would otherwise leave a
    /// row on screen for a request the app has already abandoned. And
    /// ``BreakpointCoordinator/pause(_:name:stage:timeout:resume:)`` registers its continuation on
    /// a queue of its own, so the developer can decide — and the continuation run to completion —
    /// before the thread that took the pause gets here; recording the identifier then would leave
    /// a resolved pause on record and have `stopLoading()` report an exchange as held that was let
    /// go some time ago.
    ///
    /// - Parameters:
    ///   - id: The pause's identifier.
    ///   - token: The token ``beginHold()`` gave this hold.
    private func recordPendingBreakpoint(_ id: UUID, for token: Int) {
        stateLock.lock()
        let cancelled = isCancelled
        let resolved = resolvedHold >= token
        if !cancelled && !resolved { pendingBreakpointID = id }
        stateLock.unlock()

        if cancelled { breakpoints.cancel(id: id) }
    }

    /// A mutable copy of the request with any header rewrite applied, and the log brought up to
    /// date with it.
    ///
    /// Without the second `saveRequest` a developer checking whether their rewrite worked would
    /// see the pre-rewrite headers and cURL and conclude it had not. The log is re-captured on the
    /// stubbed path too, where the copy itself is discarded: nothing goes on the wire there, but
    /// the log still has to describe the request the app would have sent.
    ///
    /// - Parameter rewrite: The merged rewrite, or `nil` when no override asked for one.
    /// - Returns: The copy, or `nil` in the impossible case that the request cannot be copied.
    private func rewrittenRequest(applying rewrite: NetworkHeaderRewrite?) -> NSMutableURLRequest? {
        guard let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            return nil
        }
        guard let rewrite else { return mutableRequest }
        rewrite.apply(to: mutableRequest)
        model.saveRequest(mutableRequest as URLRequest)
        return mutableRequest
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
    /// A delay of zero runs `work` on the caller's own thread, so a request no condition or mock
    /// delay touches keeps exactly the threading and ordering it had before rules existed. That is
    /// safe on both paths that reach here: the network path calls this from the thread
    /// `startLoading()` was given, where all `work` does is start a data task, and the stubbed
    /// path calls it from ``delayQueue``, having already left that thread to read the body. A
    /// delay above zero is scheduled on ``delayQueue`` instead of slept for — see that queue's
    /// note.
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

        /// A bandwidth ceiling paces a synthetic body exactly as it paces one off the wire, by
        /// going through the same delivery pump. Nothing else about the stub changes.
        guard !isPaced else {
            enqueueStub(response, body: body)
            return
        }

        client?.urlProtocol(self,
                            didReceive: response,
                            cacheStoragePolicy: NetworkHelper.instance.cacheStoragePolicy)

        guard !hasBeenCancelled else { return }
        client?.urlProtocol(self, didLoad: body)

        guard !hasBeenCancelled else { return }
        client?.urlProtocolDidFinishLoading(self)

        logStub(response, body: body)
    }

    /// Records a served stub in the network log.
    ///
    /// Called once the client has been handed the whole response, never before: a response the
    /// client never received — because it cancelled part-way through a paced delivery — is not
    /// one the log should claim was served.
    ///
    /// - Parameters:
    ///   - response: The response that was served.
    ///   - body: The bytes that were served with it.
    private func logStub(_ response: HTTPURLResponse, body: Data) {
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

    /// Hands a stubbed response to the pacing pump in chunks, so a bandwidth ceiling applies to it.
    ///
    /// The whole response — headers, every chunk and the terminal callback — is appended in one
    /// hop onto ``deliveryQueue``, which is the queue that owns ``pendingSteps``,
    /// ``pendingStubLog`` and ``isDraining``. Appending from here instead would touch that state
    /// from the thread the URL loading system gave us.
    ///
    /// - Parameters:
    ///   - response: The response to serve.
    ///   - body: The bytes to pace.
    private func enqueueStub(_ response: HTTPURLResponse, body: Data) {
        let chunks = Self.chunks(of: body)
        deliveryQueue.async { [weak self] in
            guard let self else { return }
            self.pendingStubLog = (response, body)
            self.pendingSteps.append(.begin(response))
            self.pendingSteps.append(contentsOf: chunks.map(PacedStep.data))
            self.pendingSteps.append(.finish(nil))
            guard !self.isDraining else { return }
            self.isDraining = true
            self.drain()
        }
    }

    /// Splits a stubbed body into the pieces the ceiling paces.
    ///
    /// A synthetic body arrives all at once, so without splitting it the ceiling would delay the
    /// whole response and then deliver it in one burst — an accurate total time, but not a
    /// throttled transfer. `URLSession` hands a real body over in chunks of its own choosing and
    /// the throttle is built for that, so a stub is cut to a comparable size.
    ///
    /// An empty body still yields one empty chunk, so a paced stub delivers the same callbacks in
    /// the same order as an unpaced one.
    ///
    /// - Parameter body: The whole synthetic body.
    /// - Returns: The body in order, in pieces of at most ``stubChunkSize`` bytes.
    private static func chunks(of body: Data) -> [Data] {
        guard body.count > stubChunkSize else { return [body] }
        return stride(from: 0, to: body.count, by: stubChunkSize).map { start in
            body.subdata(in: start..<min(start + stubChunkSize, body.count))
        }
    }

    /// Fails the request with the error a condition rule asked for, and logs the attempt.
    ///
    /// The client is told only while it is still listening, exactly as ``serve(_:body:)`` and
    /// ``forwardWithheld(_:body:)`` are: a `stopLoading()` can land between the check its callers
    /// made and this call, and messaging a client that has been told to stop is something the
    /// `URLProtocol` contract forbids.
    ///
    /// The log entry is written either way. Unlike a stub, a failure entry is not a claim that the
    /// app received anything, and a request that was attempted and then cancelled is one the
    /// developer should still be able to see — which is what the ordinary cancelled path records
    /// too.
    ///
    /// - Parameter error: The error to surface to the caller.
    private func finishWithFailure(_ error: URLError) {
        if !hasBeenCancelled {
            client?.urlProtocol(self, didFailWithError: error)
        }

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
    /// The flag and the task are read together under `stateLock` so that a delay block running
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
    /// its operation queue, the logged `HTTPRequest` and the whole response body.
    /// A pause is cancelled in the same breath, and for the same reason: a held exchange whose
    /// client has gone away must deliver nothing and must stop occupying a row in the editor.
    /// Because nothing blocks, the cancellation reaches the pause immediately — a blocked wait
    /// would have blocked the very call that ends it.
    override open func stopLoading() {
        stateLock.lock()
        isCancelled = true
        let task = startedTask
        let session = self.session
        let heldPause = pendingBreakpointID
        pendingBreakpointID = nil
        stateLock.unlock()

        if let heldPause { breakpoints.cancel(id: heldPause) }
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
    /// before rules existed. With one, they are handed to `deliveryQueue` and this returns at
    /// once: the wait is scheduled, not slept for, so the session's delegate queue stays free and
    /// a `stopLoading()` can never queue behind the pacing.
    ///
    /// A response held at a breakpoint forwards nothing at all: the bytes are buffered and the
    /// whole body is offered for editing once the load finishes. A chunk already forwarded cannot
    /// be taken back, so withholding is the only way to offer an editable response.
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        responseData?.append(data)

        guard heldBreakpoint == nil else { return }

        guard isPaced else {
            client?.urlProtocol(self, didLoad: data)
            return
        }
        enqueue(.data(data))
    }

    /// Announces a response — or the next part of one — to the client.
    ///
    /// A paced response announces its parts through `deliveryQueue` alongside its bytes, so that
    /// a second part of a `multipart/x-mixed-replace` response cannot be announced while the first
    /// part's body is still being forwarded. The disposition is answered here regardless, because
    /// the session waits on it before delivering anything more.
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.response = response
        responseData = NSMutableData()

        if heldBreakpoint != nil {
            /// Withheld along with the body. Announcing the response now would tell the app a
            /// status the developer may be about to change.
        } else if isPaced {
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
                pendingStubLog = nil
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
                if let stub = pendingStubLog {
                    logStub(stub.response, body: stub.body)
                    pendingStubLog = nil
                }
                /// A stubbed request never started a task, so there is no session to invalidate;
                /// the optional chain is what makes the two paths share this one step.
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
    /// Cancellation is re-checked here, as ``serve(_:body:)``, ``forwardWithheld(_:body:)`` and
    /// ``drain()`` re-check it between their own callbacks. Every caller reaches this after having
    /// already handed the client something — a response, or a body, either of which the client is
    /// entitled to cancel from inside — and one caller, the non-holdable branch of
    /// ``finishHeldResponse(error:request:)``, can be reached with nothing forwarded at all
    /// because the request was cancelled before the load completed. Messaging a client that has
    /// been told to stop is something the `URLProtocol` contract forbids.
    ///
    /// - Parameter error: The failure, or `nil` when the load succeeded.
    private func deliverTerminal(_ error: Error?) {
        guard !hasBeenCancelled else { return }

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
    /// instance, the session, its operation queue, the logged `HTTPRequest` and an
    /// `NSMutableData` holding the entire response body. It goes last, after the client has been
    /// told how the load ended, and `finishTasksAndInvalidate()` rather than
    /// `invalidateAndCancel()` so that a callback still in flight on the delegate queue is allowed
    /// to finish.
    ///
    /// A paced response reports both through `deliveryQueue` instead. The task finishes as soon
    /// as the last bytes are off the socket, which is well before the ceiling has finished handing
    /// them to the client, and telling the client the load had finished at that point would have
    /// it believe a body it had not yet received was complete.
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        /// Only the request is carried into the held path, never the task or the session: the
        /// continuation runs on another queue entirely and takes only values with it.
        let originalRequest = task.originalRequest

        if heldBreakpoint != nil {
            finishHeldResponse(error: error, request: originalRequest)
            return
        }

        defer {
            if isPaced {
                enqueue(.finish(error))
            } else {
                deliverTerminal(error)
                session.finishTasksAndInvalidate()
            }
        }

        recordCompletion(request: originalRequest,
                         error: error,
                         response: response,
                         data: (responseData ?? NSMutableData()) as Data)
    }

    /// Writes this exchange to the network log.
    ///
    /// Takes the response and body rather than reading them off the instance, because a held
    /// response is logged as the developer left it and not as it came off the wire. What the app
    /// received and what the log shows are then the same thing, which is the whole point of the
    /// log.
    ///
    /// - Parameters:
    ///   - request: The request as sent, or `nil` when the task carried none.
    ///   - error: The failure, or `nil` on success.
    ///   - response: The response the app received, or `nil` when there was none.
    ///   - data: The body the app received.
    private func recordCompletion(request: URLRequest?,
                                  error: Error?,
                                  response: URLResponse?,
                                  data: Data) {
        guard let request else {
            NotificationCenter.default.post(name: .LoggerReloadData, object: nil)
            return
        }

        model.saveRequestBody(request)
        model.logRequest(request)

        if error != nil {
            model.saveErrorResponse()
        } else if let response {
            model.saveResponse(response, data: data)
        }

        let capturedModel = model
        Task { @MainActor in
            await NetworkLogger.instance.add(capturedModel)
            NotificationCenter.default.post(name: .LoggerReloadData, object: nil)
        }
    }

    /// Offers the buffered response for editing, and **returns**, leaving the delegate queue free.
    ///
    /// The response and every byte of its body have been withheld up to this point, so the app has
    /// received nothing and the whole exchange is still editable. The resolved response is emitted
    /// from ``deliveryQueue`` when the decision arrives: the coordinator's queue is shared by every
    /// live pause and forwarding a body writes it to the log, which would put this request's disk
    /// I/O in front of another pause's cancellation.
    ///
    /// Three things are not held, because there is nothing to edit or nothing worth stalling for:
    /// a load that failed, a response that is not HTTP, and a body over
    /// ``maximumHeldResponseBytes``. Each of those forwards what was withheld immediately, so the
    /// app is never left short of bytes that did arrive.
    ///
    /// A held response is delivered unpaced even when a condition set a bandwidth ceiling. The
    /// developer is already sitting on the whole body by the time it is let go, and dribbling out
    /// a body they have just edited measures nothing.
    ///
    /// - Parameters:
    ///   - error: The failure the load ended with, or `nil` on success.
    ///   - request: The request as sent, for the log.
    private func finishHeldResponse(error: Error?, request: URLRequest?) {
        let buffered = (responseData ?? NSMutableData()) as Data
        let httpResponse = response as? HTTPURLResponse

        if buffered.count > maximumHeldResponseBytes {
            logMessage("Response breakpoint skipped: \(buffered.count) bytes is over the \(maximumHeldResponseBytes) byte limit for a held response.")
        }

        guard let held = heldBreakpoint,
              error == nil,
              let httpResponse,
              buffered.count <= maximumHeldResponseBytes else {
            forwardWithheld(response, body: buffered)
            recordCompletion(request: request, error: error, response: response, data: buffered)
            deliverTerminal(error)
            invalidatePrivateSession()
            return
        }

        let draft = BreakpointDraft(response: httpResponse, body: buffered)
        model.breakpointNames.append(held.name)

        let token = beginHold()
        let id = breakpoints.pause(draft,
                                   name: held.name,
                                   stage: .response,
                                   timeout: breakpointTimeoutOverride ?? held.timeout) { [self] resolution in
            endHold(token)

            deliveryQueue.async { [self] in
                guard !hasBeenCancelled else { return }

                let resolved: (response: HTTPURLResponse, body: Data)
                switch resolution {
                case .continue(let edited):
                    model.wasEdited = model.wasEdited || edited != draft

                    /// An edit that cannot be turned back into a response — a status code
                    /// `HTTPURLResponse` refuses, or a response with no URL to build one against —
                    /// falls back to what came off the wire. Handing the app nothing because a
                    /// status code was mistyped would be a worse answer than handing it the real
                    /// response.
                    let url = httpResponse.url ?? request?.url ?? self.request.url
                    resolved = url.flatMap { edited.makeResponse(url: $0) } ?? (httpResponse, buffered)

                case .timedOut:
                    resolved = (httpResponse, buffered)

                case .abort(let code):
                    model.saveErrorResponse()
                    finishWithFailure(URLError(code))
                    invalidatePrivateSession()
                    return
                }

                forwardWithheld(resolved.response, body: resolved.body)
                recordCompletion(request: request, error: nil, response: resolved.response, data: resolved.body)
                deliverTerminal(nil)
                invalidatePrivateSession()
            }
        }

        recordPendingBreakpoint(id, for: token)
    }

    /// Hands the client the response and body that were withheld while the exchange was held.
    ///
    /// Cancellation is re-checked between the two callbacks, as ``serve(_:body:)`` does: a client
    /// is entitled to cancel from inside the response callback, and delivering to a client that
    /// has been told to stop is something the `URLProtocol` contract forbids.
    ///
    /// - Parameters:
    ///   - response: The response to announce, or `nil` when none arrived.
    ///   - body: The body to forward. An empty body forwards nothing, exactly as a response with
    ///     no bytes on the wire would.
    private func forwardWithheld(_ response: URLResponse?, body: Data) {
        guard !hasBeenCancelled else { return }
        if let response {
            client?.urlProtocol(self,
                                didReceive: response,
                                cacheStoragePolicy: NetworkHelper.instance.cacheStoragePolicy)
        }

        guard !hasBeenCancelled, !body.isEmpty else { return }
        client?.urlProtocol(self, didLoad: body)
    }

    /// Invalidates the private session, if one was ever created.
    ///
    /// `finishTasksAndInvalidate()` rather than `invalidateAndCancel()`, so a callback still in
    /// flight on the delegate queue is allowed to finish. This is what releases the session's
    /// strong reference to this instance as its delegate.
    private func invalidatePrivateSession() {
        stateLock.withLock { session }?.finishTasksAndInvalidate()
    }

    /// Follows a redirect, stripping the two markers that must not travel with it and re-applying
    /// the one that must.
    ///
    /// The internal marker comes off so the redirect is intercepted and logged like any other
    /// request rather than slipping past unlogged. The replay marker comes off for the mirror
    /// reason: the entry a redirect produces is a request in its own right, and leaving the
    /// provenance on it would list the same original's Replays section twice over for what was
    /// one resend.
    ///
    /// ``ScytherOriginatedRequest``'s marker goes the other way and is stamped **on**. The
    /// redirect of a request Scyther made is still a request Scyther made, and the whole point of
    /// stripping the internal marker is that the redirect is re-examined from scratch — so
    /// without this a `301` on Scyther's own endpoint would land the follow-up in front of every
    /// breakpoint and override the original was exempt from. It is set explicitly rather than
    /// relied upon to survive, because the request handed to this delegate method is one the URL
    /// loading system built, not one Scyther copied.
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let carriesInternalMarker = URLProtocol.property(forKey: internalNetworkRequestKey, in: request) != nil
        let carriesReplayMarker = URLProtocol.property(forKey: replayOfRequestKey, in: request) != nil
        let isOriginatedByScyther = isScytherOriginated

        let updatedRequest: URLRequest
        if carriesInternalMarker || carriesReplayMarker || isOriginatedByScyther {
            let mutableRequest = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
            URLProtocol.removeProperty(forKey: internalNetworkRequestKey, in: mutableRequest)
            URLProtocol.removeProperty(forKey: replayOfRequestKey, in: mutableRequest)
            if isOriginatedByScyther {
                ScytherOriginatedRequest.mark(mutableRequest)
            }

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

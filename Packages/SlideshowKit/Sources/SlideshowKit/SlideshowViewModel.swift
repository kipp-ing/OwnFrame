import Foundation
import Observation
import PhotoSourceKit
import ThemeKit

@MainActor
@Observable
public final class SlideshowViewModel {
    public private(set) var phase: SlideshowPhase = .loading
    public private(set) var currentAssetID: String?
    public private(set) var currentImageData: Data?

    /// User-intent pause (the chrome play/pause button), distinct from the
    /// foreground/background gating done via `pause()`/`resume()`. While `true`
    /// the auto-advance ticker stays stopped even across background→foreground,
    /// but manual `showNext()`/`showPrevious()` still work.
    public private(set) var isPaused = false

    /// Why the most recent fetch failed; nil while healthy (310, FR-310-05).
    /// Set on any source/image failure, cleared by the next success. The error
    /// surface reads this only in the `.failed` phase — while an image is
    /// showing, failures stay invisible (FR-310-03/09).
    public private(set) var failureReason: SlideshowFailureReason?

    /// The collection currently being shown (Immich album / PhotoKit collection ID).
    /// Mutable so Home-Assistant/remote control can switch sources at runtime (see
    /// `switchAlbum(_:)`). Also the snapshot/cache scoping key.
    public private(set) var albumID: String
    private let source: any PhotoSourceProviding
    private let ticker: any SlideshowTicker
    /// Monotonic clock for retry backoff and refresh staleness (310, FR-310-12).
    private let clock: any SlideshowClock
    private let cache: ImageCache
    /// Persistence tier under the RAM cache (320): photos survive outages and
    /// relaunches. nil = exact 310 behavior (the compatibility contract).
    private let diskCache: (any DiskImageStoring)?
    /// Remembered photo list per source (320, FR-320-06/07): written on every
    /// successful fetch, played back when a launch-time fetch fails. Same
    /// nil-means-310 contract as `diskCache`.
    private let snapshots: (any SourceSnapshotStoring)?
    private let config: SlideshowConfig
    /// Live display/playback preferences (order, duration, quality). Read at the
    /// point of use so changes apply to the running show without a restart (008).
    private let settingsStore: any ThemeSettingsStore
    /// RNG for the shuffle play order; injectable so shuffle is deterministic in tests.
    private var rng: AnyRandomNumberGenerator
    private var imageAssets: [SourceAsset] = []

    /// The play order for the current cycle — a permutation of asset indices.
    /// Sequential is album order; shuffle is a random permutation that reshuffles each
    /// cycle (D4). `cursor` is the position of the currently shown photo within it.
    private var playOrder: [Int] = []
    private var cursor = 0
    private var builtOrder: PlayOrder?
    private var runTask: Task<Void, Never>?

    // MARK: Auto-retry state (310, US1)

    /// Which operation the pending retry re-attempts: the source list fetch
    /// (start/refresh path) or an image load that exhausted the cycle (step
    /// path) — research R4.
    private enum PendingRetry {
        case sourceReload
        case imageReload
    }

    private var retryPolicy: RetryPolicy
    private var retryTask: Task<Void, Never>?
    private var pendingRetry: PendingRetry?
    /// Monotonic due time of the pending retry — survives `pause()` so a
    /// foreground return can resume or fire an overdue attempt (FR-310-10).
    private var nextRetryDue: Duration?
    /// Last error seen by `loadFromCursor` — the walk swallows per-photo errors,
    /// but the retry needs one for classification and backoff.
    private var lastLoadError: (any Error)?

    // MARK: Periodic refresh state (310, US2)

    private var refreshTask: Task<Void, Never>?
    /// Monotonic stamp of the last successful asset-list fetch — initial load,
    /// hourly refresh, or a retry that recovered the source (FR-310-06).
    private var lastSuccessfulRefresh: Duration?

    public init(
        source: any PhotoSourceProviding,
        collectionID: String,
        ticker: any SlideshowTicker,
        clock: any SlideshowClock = ContinuousSlideshowClock(),
        retryPolicy: RetryPolicy = RetryPolicy(),
        diskCache: (any DiskImageStoring)? = nil,
        snapshots: (any SourceSnapshotStoring)? = nil,
        cache: ImageCache = ImageCache(limit: SlideshowConfig.default.cacheLimit),
        config: SlideshowConfig = .default,
        settingsStore: any ThemeSettingsStore,
        rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
    ) {
        self.source = source
        self.albumID = collectionID
        self.ticker = ticker
        self.clock = clock
        self.retryPolicy = retryPolicy
        self.diskCache = diskCache
        self.snapshots = snapshots
        self.cache = cache
        self.config = config
        self.settingsStore = settingsStore
        self.rng = AnyRandomNumberGenerator(rng)
    }

    public func start() async {
        stopTicker()
        // Rebind every timer to whatever this start() targets: a source switch
        // must never leave a retry or refresh running against the old source
        // (FR-310-11), and an explicit (re)start begins a fresh backoff curve.
        cancelRetry()
        cancelRefresh()
        retryPolicy.reset()
        isPaused = false
        phase = .loading

        do {
            // R10: the source's readiness precondition (Immich = 130 FR-130-05/06 server-version
            // gate; Photos = authorization) up front, so a relaunch straight into the slideshow
            // (bypassing onboarding) still surfaces the upgrade/permission notice.
            try await source.ensureReady()
            imageAssets = try await source.assets(in: albumID).filter { $0.kind == .image }
            markRefreshSucceeded(with: imageAssets)
            guard !imageAssets.isEmpty else {
                resetCurrent()
                failureReason = nil
                phase = .empty
                return
            }

            rebuildSequence(order: settingsStore.settings.order, anchorAssetIndex: nil)
            if let loaded = await loadFromCursor(forward: true) {
                showLoadedImage(loaded)
                failureReason = nil
                phase = .playing
                prefetchImages()
                startTickerLoop()
            } else {
                // The list arrived but no photo loads: keep whatever is on
                // screen (FR-310-03) and retry the image loads in the background.
                handleFailure(lastLoadError ?? EngineFailure.noLoadableImage, kind: .imageReload)
            }
        } catch {
            // 320 FR-320-07: stale-beats-broken extends to launch — a
            // remembered list plays from disk while the retry recovers live
            // data. handleFailure sees the shown image and lands on
            // .playing-degraded; without a playable snapshot it is the calm
            // state, auto-retry behind it either way (310 US1-2).
            // A too-old server (130) must show the upgrade notice, not silently play cached
            // photos — skip the offline snapshot fallback for that terminal case.
            if !RetryPolicy.classify(Self.sourceFailure(from: error)).isTerminal, await startFromSnapshot() {
                handleFailure(error, kind: .sourceReload)
                startTickerLoop()
            } else {
                handleFailure(error, kind: .sourceReload)
            }
        }
    }

    /// Offline startup fallback (320, US2): adopt the remembered list and show
    /// the first loadable photo from the disk tier. False when no snapshot
    /// exists or every remembered photo is gone (purged) — the caller then
    /// takes the ordinary failure path (SC-320-06).
    private func startFromSnapshot() async -> Bool {
        guard let snapshot = snapshots?.load(forKey: albumID)?.filter({ $0.kind == .image }),
              !snapshot.isEmpty else {
            return false
        }

        imageAssets = snapshot
        rebuildSequence(order: settingsStore.settings.order, anchorAssetIndex: nil)
        guard let loaded = await loadFromCursor(forward: true) else {
            return false
        }

        showLoadedImage(loaded)
        prefetchImages()
        return true
    }

    public func advance() async {
        await step(forward: true)
    }

    /// Manual forward step from the chrome/swipe. Unlike the ticker-driven
    /// `advance()`, it resets the auto-advance timer so the next automatic step
    /// is a full interval away; works while paused (without resuming the timer).
    public func showNext() async {
        stopTicker()
        await step(forward: true)
        restartTickerIfPlaying()
    }

    /// Manual backward step from the chrome/swipe (the only place the show moves
    /// backwards). Resets the auto-advance timer like `showNext()`.
    public func showPrevious() async {
        stopTicker()
        await step(forward: false)
        restartTickerIfPlaying()
    }

    /// Toggle the user-intent pause (chrome play/pause button). Pausing stops the
    /// auto-advance; resuming restarts it only while a real image is on screen.
    public func togglePause() {
        if isPaused {
            isPaused = false
            restartTickerIfPlaying()
        } else {
            isPaused = true
            stopTicker()
        }
    }

    /// Jump straight to a specific asset in the current album (album-browser tap).
    /// No-op if the album doesn't contain it. Resets the auto-advance timer.
    public func jump(to assetID: String) async {
        guard let assetIndex = imageAssets.firstIndex(where: { $0.id == assetID }) else {
            return
        }

        stopTicker()
        ensureSequenceForCurrentOrder()
        if let position = playOrder.firstIndex(of: assetIndex) {
            cursor = position
        }
        if let loaded = await loadFromCursor(forward: true) {
            showLoadedImage(loaded)
            phase = .playing
            prefetchImages()
            restartTickerIfPlaying()
            // Same recovery acknowledgement as step(): a successful jump
            // obsoletes a pending IMAGE retry — and, as in step(), must leave
            // a SOURCE retry running (the jump may have loaded from disk).
            if pendingRetry == .imageReload {
                clearFailure()
                armRefreshTask()
            }
        } else {
            phase = .failed
        }
    }

    /// Shared forward/backward step: honors the live order (rebuilding the sequence if
    /// it changed, keeping the current photo as the anchor), moves the cursor one step,
    /// and loads the first available photo from there, or fails the show if none load.
    private func step(forward: Bool) async {
        guard phase == .playing, !imageAssets.isEmpty else {
            return
        }

        ensureSequenceForCurrentOrder()
        let displayedCursor = cursor
        moveCursor(forward: forward)

        if let loaded = await loadFromCursor(forward: forward) {
            showLoadedImage(loaded)
            prefetchImages()
            // A successful step during an IMAGE outage is the recovery: drop
            // the pending retry so it can't fire minutes later, re-show a
            // photo, or reset the advance timer (stale-retry bug). A pending
            // SOURCE retry must survive (320): with the disk tier, this step
            // may have loaded from disk and proves nothing about the server —
            // cancelling it would strand an offline-relaunched frame with no
            // recovery path at all (no refresh is armed before the first
            // successful fetch).
            if pendingRetry == .imageReload {
                clearFailure()
                armRefreshTask()
            }
        } else {
            // Every photo in the cycle failed to load: keep the current image
            // on screen (FR-310-03), park the pointless auto-advance, and let
            // the backoff retry recover the show (US1-1). Restore the cursor to
            // the displayed photo — the failed walk left it one slot ahead, and
            // recovery must resume on what is visible, not jump mid-slot
            // (recovery-jump / paused-jump bugs).
            cursor = displayedCursor
            stopTicker()
            handleFailure(lastLoadError ?? EngineFailure.noLoadableImage, kind: .imageReload)
        }
    }

    private func restartTickerIfPlaying() {
        guard phase == .playing, !isPaused else {
            return
        }
        startTickerLoop()
    }

    public func retry() async {
        guard phase == .failed || pendingRetry != nil else {
            return
        }

        // FR-310-04: an immediate attempt that also resets the backoff. From
        // the calm error state this is the explicit restart (with its loading
        // feedback); from a playing-but-degraded show it re-attempts quietly.
        let kind = pendingRetry
        cancelRetry()
        retryPolicy.reset()
        if phase == .failed {
            await start()
        } else if kind == .sourceReload {
            await reloadSource()
        } else {
            await reloadImageFromCursor()
        }
    }

    // MARK: - Auto-retry (310, US1)

    /// Record a failure, classify it, and arm the backoff retry. The phase only
    /// becomes `.failed` when there is nothing on screen (FR-310-03).
    private func handleFailure(_ error: any Error, kind: PendingRetry) {
        let failure = Self.sourceFailure(from: error)
        let reason = RetryPolicy.classify(failure)
        failureReason = reason
        if currentImageData == nil {
            resetCurrent()
            phase = .failed
        } else {
            phase = .playing
        }
        // 130 FR-130-06: an unsupported (v<3) server is terminal — surface the notice, but do
        // not arm the backoff loop against a server the app can never satisfy.
        guard !reason.isTerminal else {
            cancelRetry()
            return
        }
        scheduleRetry(for: failure, kind: kind)
    }

    private func scheduleRetry(for failure: SourceFailure, kind: PendingRetry) {
        pendingRetry = kind
        let delay = retryPolicy.nextDelay(for: failure)
        nextRetryDue = clock.now + delay
        armRetryTask(delay: delay)
    }

    private func armRetryTask(delay: Duration) {
        retryTask?.cancel()
        let clock = clock
        retryTask = Task.detached { [weak self, clock] in
            do {
                try await clock.sleep(for: delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else {
                return
            }
            await self.performRetryAttempt()
        }
    }

    private func performRetryAttempt() async {
        guard let kind = pendingRetry else {
            return
        }

        switch kind {
        case .sourceReload:
            await reloadSource()
        case .imageReload:
            await reloadImageFromCursor()
        }
    }

    /// Quiet source re-fetch: the shared operation behind the backoff retry AND
    /// the hourly refresh — no loading state, no visible transition. Success
    /// clears the failure, resets the backoff, stamps the refresh schedule
    /// (research R4), and — while the show is playing — merges the fresh list
    /// via RotationReconciler instead of rebuilding (FR-310-07/08).
    private func reloadSource() async {
        do {
            // R10: re-check readiness on every refresh so a source that lost its precondition
            // mid-run (Immich downgraded to v2 / Photos access revoked) surfaces the notice
            // terminally instead of looping the backoff.
            try await source.ensureReady()
            let assets = try await source.assets(in: albumID).filter { $0.kind == .image }
            clearFailure()
            markRefreshSucceeded(with: assets)

            guard !assets.isEmpty else {
                imageAssets = []
                resetCurrent()
                stopTicker()
                phase = .empty
                return
            }

            if phase == .playing, currentImageData != nil {
                applyReconciledAssets(assets)
                return
            }

            imageAssets = assets
            rebuildSequence(order: settingsStore.settings.order, anchorAssetIndex: nil)
            if let loaded = await loadFromCursor(forward: true) {
                showLoadedImage(loaded)
                phase = .playing
                prefetchImages()
                restartTickerIfPlaying()
            } else {
                handleFailure(lastLoadError ?? EngineFailure.noLoadableImage, kind: .imageReload)
            }
        } catch {
            handleFailure(error, kind: .sourceReload)
        }
    }

    /// Merge a fresh asset list into the running rotation without touching the
    /// on-screen photo, the auto-advance wait, or the cycle position
    /// (FR-310-07). Only the prefetch is re-pointed at the new remainder.
    private func applyReconciledAssets(_ assets: [SourceAsset]) {
        let order = builtOrder ?? settingsStore.settings.order
        let result = RotationReconciler.reconcile(
            oldAssets: imageAssets, newAssets: assets,
            playOrder: playOrder, cursor: cursor,
            order: order, currentAssetID: currentAssetID,
            rng: &rng
        )
        imageAssets = assets
        playOrder = result.playOrder
        cursor = result.cursor
        prefetchImages()
    }

    // MARK: - Periodic refresh (310, US2)

    /// Stamp the successful list fetch and (re)arm the next hourly refresh —
    /// runs across `.playing`, `.empty`, and `.failed` so an emptied or broken
    /// source recovers on its own (FR-310-06). This is the single "list fetch
    /// succeeded" choke point, so the source snapshot rides it (320,
    /// FR-320-06) — with the fresh list passed in, because reloadSource calls
    /// this before `imageAssets` is reassigned.
    private func markRefreshSucceeded(with assets: [SourceAsset]) {
        snapshots?.save(assets, forKey: albumID)
        lastSuccessfulRefresh = clock.now
        armRefreshTask()
    }

    private func armRefreshTask() {
        refreshTask?.cancel()
        guard let last = lastSuccessfulRefresh else {
            return
        }

        let due = last + config.refreshInterval
        let delay = max(due - clock.now, .zero)
        let clock = clock
        refreshTask = Task.detached { [weak self, clock] in
            do {
                try await clock.sleep(for: delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else {
                return
            }
            await self.refreshTaskFired()
        }
    }

    private func refreshTaskFired() async {
        // While a retry is pending, the retry owns the source: its success is
        // itself the refresh and re-arms the schedule (FR-310-09, research R4).
        guard pendingRetry == nil else {
            return
        }
        await reloadSource()
    }

    private func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        lastSuccessfulRefresh = nil
    }

    /// Re-attempt the image load that exhausted the cycle (US1-1): on success
    /// the show moves to the photo under the cursor and the ticker re-arms.
    private func reloadImageFromCursor() async {
        guard !imageAssets.isEmpty else {
            await reloadSource()
            return
        }

        if let loaded = await loadFromCursor(forward: true) {
            showLoadedImage(loaded)
            clearFailure()
            phase = .playing
            prefetchImages()
            restartTickerIfPlaying()
            // A refresh that came due during the outage was consumed by the
            // pending-retry guard — re-arm it (fires immediately if overdue).
            armRefreshTask()
        } else {
            handleFailure(lastLoadError ?? EngineFailure.noLoadableImage, kind: .imageReload)
        }
    }

    private func clearFailure() {
        retryPolicy.reset()
        failureReason = nil
        cancelRetry()
    }

    /// Fully discard the pending retry (rebind/handled): task, kind, and due time.
    private func cancelRetry() {
        retryTask?.cancel()
        retryTask = nil
        pendingRetry = nil
        nextRetryDue = nil
    }

    /// Background gating (scenePhase → inactive/background): stops the
    /// auto-advance AND suspends the retry/refresh timers — nothing fires while
    /// backgrounded (FR-310-10). Their due state survives for `resume()`.
    public func pause() {
        stopTicker()
        retryTask?.cancel()
        retryTask = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    public func resume() {
        // Re-arm the background work first — independent of the user-intent
        // pause (a paused frame still refreshes its list and recovers its
        // connection; research R7). Overdue work fires immediately (US3).
        if pendingRetry != nil {
            let remaining = max((nextRetryDue ?? clock.now) - clock.now, .zero)
            armRetryTask(delay: remaining)
        }
        armRefreshTask()

        // The ticker only re-arms while actually playing; if the user paused
        // via the chrome, stay paused across background→foreground.
        guard phase == .playing, !isPaused else {
            return
        }

        startTickerLoop()
    }

    /// Stop only the auto-advance loop — the internal "hold the slide" used by
    /// manual steps, user pause, and teardown. Never touches retry/refresh.
    private func stopTicker() {
        runTask?.cancel()
        runTask = nil
    }

    /// Switch to a different album and reload from its first image. Used by remote
    /// control (HA select); a no-op restart if the album is unchanged.
    public func switchAlbum(_ albumID: String) async {
        self.albumID = albumID
        await start()
    }

    private func startTickerLoop() {
        stopTicker()
        let ticker = ticker
        runTask = Task.detached { [weak self, ticker] in
            guard let self else { return }

            while !Task.isCancelled {
                // Review R1: read the live duration on the MainActor at the top of each
                // cycle (never read @MainActor store state from the detached task), then
                // sleep that value. A duration change auto-applies on the next cycle.
                let duration = await self.currentTickDuration()
                do {
                    try await ticker.waitForNextTick(duration: duration)
                    if Task.isCancelled {
                        break
                    }
                    await self.advance()
                } catch is CancellationError {
                    break
                } catch {
                    break
                }
            }
        }
    }

    private func currentTickDuration() -> Duration {
        settingsStore.settings.duration
    }

    // MARK: - Play sequence

    /// Rebuild the play order if `settings.order` changed since it was last built,
    /// keeping the currently shown photo as the cursor anchor (order-switch edge case).
    private func ensureSequenceForCurrentOrder() {
        let order = settingsStore.settings.order
        guard builtOrder != order || playOrder.count != imageAssets.count else {
            return
        }
        rebuildSequence(order: order, anchorAssetIndex: currentAssetIndex)
    }

    private func rebuildSequence(order: PlayOrder, anchorAssetIndex: Int?) {
        var indices = Array(0..<imageAssets.count)
        if order == .shuffle {
            indices.shuffle(using: &rng)
        }
        playOrder = indices
        builtOrder = order
        if let anchor = anchorAssetIndex, let position = playOrder.firstIndex(of: anchor) {
            cursor = position
        } else {
            cursor = 0
        }
    }

    /// Asset index of the photo currently under the cursor, if the sequence is loaded.
    private var currentAssetIndex: Int? {
        guard cursor >= 0, cursor < playOrder.count else {
            return nil
        }
        return playOrder[cursor]
    }

    private func moveCursor(forward: Bool) {
        let count = playOrder.count
        guard count > 0 else {
            return
        }

        if forward {
            if cursor + 1 >= count {
                startNewCycle()
                cursor = 0
            } else {
                cursor += 1
            }
        } else {
            cursor = (cursor - 1 + count) % count
        }
    }

    /// Begin a fresh cycle. Shuffle reshuffles (avoiding an immediate repeat of the
    /// photo that just ended the previous cycle); sequential repeats the album order.
    private func startNewCycle() {
        guard settingsStore.settings.order == .shuffle, playOrder.count > 1 else {
            return
        }

        let lastShown = playOrder[playOrder.count - 1]
        playOrder.shuffle(using: &rng)
        if playOrder[0] == lastShown {
            playOrder.swapAt(0, 1)
        }
    }

    /// Try to load starting at the current cursor, walking the play order in
    /// `direction` past unloadable photos, up to one full cycle. Returns the shown
    /// image or nil if every photo in the cycle failed.
    private func loadFromCursor(forward: Bool) async -> LoadedImage? {
        let count = playOrder.count
        guard count > 0 else {
            return nil
        }

        var attempts = 0
        while attempts < count {
            let assetID = imageAssets[playOrder[cursor]].id
            do {
                let data = try await loadImageData(for: assetID)
                return LoadedImage(assetID: assetID, data: data)
            } catch {
                lastLoadError = error
                moveCursor(forward: forward)
                attempts += 1
            }
        }

        return nil
    }

    /// RAM → disk → network (320, FR-320-02): a disk hit repopulates RAM and
    /// makes no network request; a network fetch writes through to both tiers.
    private func loadImageData(for assetID: String) async throws -> Data {
        let quality = settingsStore.settings.quality
        let key = cacheKey(for: assetID, quality: quality)

        if let cached = cache.data(for: key) {
            return cached
        }

        if let diskCache, let stored = await diskCache.data(forKey: key) {
            cache.store(stored, for: key)
            return stored
        }

        let data = try await source.imageData(for: assetID, fidelity: Self.fidelity(for: quality))
        cache.store(data, for: key)
        persistToDisk(data, key: key)
        return data
    }

    /// Fire-and-forget disk write: storing (and the pruning it triggers) never
    /// blocks or delays the visible slide transition (FR-320-11).
    private func persistToDisk(_ data: Data, key: String) {
        guard let diskCache else {
            return
        }
        Task.detached {
            await diskCache.store(data, forKey: key)
        }
    }

    private func cacheKey(for assetID: String, quality: ImageQuality) -> String {
        "\(assetID)#\(quality.rawValue)"
    }

    /// Maps the display-quality tier (ThemeKit) to the neutral fidelity the source serves
    /// (R6). The two enums share the "preview"/"original" raw values, so the cache key above
    /// (`"\(id)#\(quality.rawValue)"`) stays byte-identical to the pre-900 one — fielded 320
    /// disk caches keep hitting.
    private static func fidelity(for quality: ImageQuality) -> ImageFidelity {
        switch quality {
        case .preview: return .preview
        case .original: return .original
        }
    }

    /// Coerce a caught error into the neutral taxonomy `RetryPolicy` classifies. Sources throw
    /// `SourceFailure`; anything else (the defensive fallbacks below, an unexpected transport
    /// surprise) is treated as transient — the same category the pre-900 engine gave every
    /// non-auth, non-serverTooOld error.
    private static func sourceFailure(from error: any Error) -> SourceFailure {
        error as? SourceFailure ?? .transient(underlying: error)
    }

    private func showLoadedImage(_ loaded: LoadedImage) {
        currentAssetID = loaded.assetID
        currentImageData = loaded.data
    }

    private func resetCurrent() {
        currentAssetID = nil
        currentImageData = nil
        playOrder = []
        cursor = 0
        builtOrder = nil
    }

    /// Prefetch the next `prefetchDepth` photos along the play order (D4) so an advance
    /// shows an already-loaded image.
    private func prefetchImages() {
        let quality = settingsStore.settings.quality
        let count = playOrder.count
        guard count > 0 else {
            return
        }

        let depth = min(config.prefetchDepth, max(count - 1, 0))
        guard depth > 0 else {
            return
        }

        let assetIDs = (1...depth).map { offset in
            imageAssets[playOrder[(cursor + offset) % count]].id
        }
        let source = source
        let cache = cache
        let diskCache = diskCache

        Task { [quality] in
            for assetID in assetIDs {
                let key = cacheKey(for: assetID, quality: quality)
                guard cache.data(for: key) == nil else {
                    continue
                }

                // Same tiering as the display path: disk beats network, and a
                // fetched prefetch writes through to disk (FR-320-01). Awaiting
                // the store here is fine — the prefetch task is already off the
                // display path.
                if let diskCache, let stored = await diskCache.data(forKey: key) {
                    cache.store(stored, for: key)
                    continue
                }

                do {
                    let data = try await source.imageData(for: assetID, fidelity: Self.fidelity(for: quality))
                    cache.store(data, for: key)
                    await diskCache?.store(data, forKey: key)
                } catch {
                    continue
                }
            }
        }
    }
}

private struct LoadedImage {
    let assetID: String
    let data: Data
}

/// Neutral placeholder for the defensive `?? ` arms where the cursor walk exhausted without
/// capturing a concrete source error. Coerced to `.transient` (via `sourceFailure(from:)`) —
/// matching the classification the pre-900 `ImmichError.invalidResponse` fallback carried.
private enum EngineFailure: Error {
    case noLoadableImage
}

/// Type-erased RNG so the view model can store an injected generator (system in
/// production, seeded in tests) and still pass it `inout` to `Array.shuffle(using:)`.
private struct AnyRandomNumberGenerator: RandomNumberGenerator {
    private var base: any RandomNumberGenerator

    init(_ base: any RandomNumberGenerator) {
        self.base = base
    }

    mutating func next() -> UInt64 {
        base.next()
    }
}

import Foundation
import ImmichClient
import Observation
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

    /// The album currently being shown. Mutable so Home-Assistant/remote control
    /// can switch albums at runtime (see `switchAlbum(_:)`).
    public private(set) var albumID: String
    private let api: any ImmichAPI
    private let ticker: any SlideshowTicker
    /// Monotonic clock for retry backoff and refresh staleness (310, FR-310-12).
    private let clock: any SlideshowClock
    private let cache: ImageCache
    private let config: SlideshowConfig
    /// Live display/playback preferences (order, duration, quality). Read at the
    /// point of use so changes apply to the running show without a restart (008).
    private let settingsStore: any ThemeSettingsStore
    /// RNG for the shuffle play order; injectable so shuffle is deterministic in tests.
    private var rng: AnyRandomNumberGenerator
    private var imageAssets: [Asset] = []

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
        api: any ImmichAPI,
        albumID: String,
        ticker: any SlideshowTicker,
        clock: any SlideshowClock = ContinuousSlideshowClock(),
        retryPolicy: RetryPolicy = RetryPolicy(),
        cache: ImageCache = ImageCache(limit: SlideshowConfig.default.cacheLimit),
        config: SlideshowConfig = .default,
        settingsStore: any ThemeSettingsStore,
        rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
    ) {
        self.api = api
        self.albumID = albumID
        self.ticker = ticker
        self.clock = clock
        self.retryPolicy = retryPolicy
        self.cache = cache
        self.config = config
        self.settingsStore = settingsStore
        self.rng = AnyRandomNumberGenerator(rng)
    }

    public func start() async {
        pause()
        // Rebind every timer to whatever this start() targets: a source switch
        // must never leave a retry or refresh running against the old source
        // (FR-310-11), and an explicit (re)start begins a fresh backoff curve.
        cancelRetry()
        cancelRefresh()
        retryPolicy.reset()
        isPaused = false
        phase = .loading

        do {
            imageAssets = try await api.assets(albumID: albumID).filter { $0.type == "IMAGE" }
            markRefreshSucceeded()
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
                handleFailure(lastLoadError ?? ImmichError.invalidResponse, kind: .imageReload)
            }
        } catch {
            // Source list unreachable: calm state only when nothing is showing
            // (US1-2); auto-retry runs behind it either way.
            handleFailure(error, kind: .sourceReload)
        }
    }

    public func advance() async {
        await step(forward: true)
    }

    /// Manual forward step from the chrome/swipe. Unlike the ticker-driven
    /// `advance()`, it resets the auto-advance timer so the next automatic step
    /// is a full interval away; works while paused (without resuming the timer).
    public func showNext() async {
        pause()
        await step(forward: true)
        restartTickerIfPlaying()
    }

    /// Manual backward step from the chrome/swipe (the only place the show moves
    /// backwards). Resets the auto-advance timer like `showNext()`.
    public func showPrevious() async {
        pause()
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
            pause()
        }
    }

    /// Jump straight to a specific asset in the current album (album-browser tap).
    /// No-op if the album doesn't contain it. Resets the auto-advance timer.
    public func jump(to assetID: String) async {
        guard let assetIndex = imageAssets.firstIndex(where: { $0.id == assetID }) else {
            return
        }

        pause()
        ensureSequenceForCurrentOrder()
        if let position = playOrder.firstIndex(of: assetIndex) {
            cursor = position
        }
        if let loaded = await loadFromCursor(forward: true) {
            showLoadedImage(loaded)
            phase = .playing
            prefetchImages()
            restartTickerIfPlaying()
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
        moveCursor(forward: forward)

        if let loaded = await loadFromCursor(forward: forward) {
            showLoadedImage(loaded)
            prefetchImages()
        } else {
            // Every photo in the cycle failed to load: keep the current image
            // on screen (FR-310-03), park the pointless auto-advance, and let
            // the backoff retry recover the show (US1-1).
            pause()
            handleFailure(lastLoadError ?? ImmichError.invalidResponse, kind: .imageReload)
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
        failureReason = RetryPolicy.classify(error)
        if currentImageData == nil {
            resetCurrent()
            phase = .failed
        } else {
            phase = .playing
        }
        scheduleRetry(for: error, kind: kind)
    }

    private func scheduleRetry(for error: any Error, kind: PendingRetry) {
        pendingRetry = kind
        let delay = retryPolicy.nextDelay(for: error)
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
            let assets = try await api.assets(albumID: albumID).filter { $0.type == "IMAGE" }
            clearFailure()
            markRefreshSucceeded()

            guard !assets.isEmpty else {
                imageAssets = []
                resetCurrent()
                pause()
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
                handleFailure(lastLoadError ?? ImmichError.invalidResponse, kind: .imageReload)
            }
        } catch {
            handleFailure(error, kind: .sourceReload)
        }
    }

    /// Merge a fresh asset list into the running rotation without touching the
    /// on-screen photo, the auto-advance wait, or the cycle position
    /// (FR-310-07). Only the prefetch is re-pointed at the new remainder.
    private func applyReconciledAssets(_ assets: [Asset]) {
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
    /// source recovers on its own (FR-310-06).
    private func markRefreshSucceeded() {
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
            handleFailure(lastLoadError ?? ImmichError.invalidResponse, kind: .imageReload)
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

    public func pause() {
        runTask?.cancel()
        runTask = nil
    }

    public func resume() {
        // Foreground gating only re-arms the timer; if the user paused via the
        // chrome, stay paused across background→foreground.
        guard phase == .playing, !isPaused else {
            return
        }

        startTickerLoop()
    }

    /// Switch to a different album and reload from its first image. Used by remote
    /// control (HA select); a no-op restart if the album is unchanged.
    public func switchAlbum(_ albumID: String) async {
        self.albumID = albumID
        await start()
    }

    private func startTickerLoop() {
        pause()
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

    private func loadImageData(for assetID: String) async throws -> Data {
        let quality = settingsStore.settings.quality
        let key = cacheKey(for: assetID, quality: quality)

        if let cached = cache.data(for: key) {
            return cached
        }

        let data = switch quality {
        case .preview:
            try await api.preview(assetID: assetID)
        case .original:
            try await api.original(assetID: assetID)
        }
        cache.store(data, for: key)
        return data
    }

    private func cacheKey(for assetID: String, quality: ImageQuality) -> String {
        "\(assetID)#\(quality.rawValue)"
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
        let api = api
        let cache = cache

        Task { [quality] in
            for assetID in assetIDs {
                let key = cacheKey(for: assetID, quality: quality)
                guard cache.data(for: key) == nil else {
                    continue
                }

                do {
                    let data = switch quality {
                    case .preview:
                        try await api.preview(assetID: assetID)
                    case .original:
                        try await api.original(assetID: assetID)
                    }
                    cache.store(data, for: key)
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

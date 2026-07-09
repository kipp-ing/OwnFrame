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

    public init(
        api: any ImmichAPI,
        albumID: String,
        ticker: any SlideshowTicker,
        clock: any SlideshowClock = ContinuousSlideshowClock(),
        cache: ImageCache = ImageCache(limit: SlideshowConfig.default.cacheLimit),
        config: SlideshowConfig = .default,
        settingsStore: any ThemeSettingsStore,
        rng: any RandomNumberGenerator = SystemRandomNumberGenerator()
    ) {
        self.api = api
        self.albumID = albumID
        self.ticker = ticker
        self.clock = clock
        self.cache = cache
        self.config = config
        self.settingsStore = settingsStore
        self.rng = AnyRandomNumberGenerator(rng)
    }

    public func start() async {
        pause()
        isPaused = false
        phase = .loading

        do {
            imageAssets = try await api.assets(albumID: albumID).filter { $0.type == "IMAGE" }
            guard !imageAssets.isEmpty else {
                resetCurrent()
                phase = .empty
                return
            }

            rebuildSequence(order: settingsStore.settings.order, anchorAssetIndex: nil)
            if let loaded = await loadFromCursor(forward: true) {
                showLoadedImage(loaded)
                phase = .playing
                prefetchImages()
                startTickerLoop()
            } else {
                resetCurrent()
                phase = .failed
            }
        } catch {
            phase = .failed
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
            phase = .failed
            pause()
        }
    }

    private func restartTickerIfPlaying() {
        guard phase == .playing, !isPaused else {
            return
        }
        startTickerLoop()
    }

    public func retry() async {
        guard phase == .failed else {
            return
        }

        await start()
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

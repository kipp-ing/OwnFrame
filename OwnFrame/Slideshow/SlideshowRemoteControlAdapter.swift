//
//  SlideshowRemoteControlAdapter.swift
//  OwnFrame
//

import HAControlKit
import ImmichClient
import Observation
import OnboardingKit
import PhotoSourceKit
import PowerKit
import SlideshowKit
import ThemeKit
import UIKit

/// Bridges Home-Assistant remote control onto the running app: pause/play onto the
/// `SlideshowViewModel`, brightness onto the foreground-gated `PowerManager`, and the
/// source select onto the app-level source switch (900, FR-900-11 — the select lists the
/// saved LIBRARY's sources of every kind; the app owns the cross-backend rebuild). Also
/// mirrors the full `ThemeSettings` surface to HA (`SettingsControlling`): remote applies
/// are written through the theme store with the local-change callback suppressed, so
/// only genuinely local edits echo back (FR-710-12/20).
@MainActor
public final class SlideshowRemoteControlAdapter: PlaybackControlling {
    private let slideshow: SlideshowViewModel
    private let powerManager: PowerManager
    private var albums: [Album]
    private let currentAlbumID: String?
    /// The saved source library (900): the select's options. When empty, the legacy
    /// album-list select remains (pre-900 constructions and tests).
    private let sources: [Source]
    private let onSelectSource: ((String) -> Void)?
    /// The active source is Photos-backed (900): current-photo metadata/image publish
    /// through the engine's neutral pass-throughs instead of the Immich API.
    private let isPhotoLibrarySource: Bool
    private let themeStore: (any ThemeSettingsStore)?
    private var suppressSettingsCallback = false

    // Single source of truth is the ViewModel's own `isPaused` (see `observePlayback`)
    // so chrome-driven and HA-driven pauses can never drift apart.
    public var playbackState: PlaybackState { slideshow.isPaused ? .paused : .playing }
    // Current target brightness (0.0–1.0). The PowerManager itself owns the actual
    // screen and only applies it in the foreground (Konstitution V); we mirror the
    // requested target so HA echoes a stable value.
    public private(set) var brightness: Double
    public var albumOptions: [String] {
        sources.isEmpty ? albums.map(\.name) : sources.map(\.label)
    }
    public private(set) var currentAlbum: String?
    public var onLocalChange: (@MainActor () -> Void)?
    public var onSettingsChange: (@MainActor () -> Void)?
    public var onPhotoChange: (@MainActor (PhotoReport) -> Void)?

    // Photo-reporting dependencies (US2). Optional so the existing playback/settings
    // call sites keep compiling; when unwired, reports degrade to asset ID + phase
    // with no metadata or image.
    private let api: (any ImmichAPI)?
    private let metadataCache: MetadataCache
    private let publishOptions: (any HAPublishOptionsStore)?
    private var _currentPhotoReport: PhotoReport

    public init(
        slideshow: SlideshowViewModel,
        powerManager: PowerManager,
        albums: [Album] = [],
        currentAlbumID: String? = nil,
        sources: [Source] = [],
        activeSourceID: String? = nil,
        onSelectSource: ((String) -> Void)? = nil,
        isPhotoLibrarySource: Bool = false,
        initialBrightness: Double = 1.0,
        themeStore: (any ThemeSettingsStore)? = nil,
        api: (any ImmichAPI)? = nil,
        metadataCache: MetadataCache = MetadataCache(limit: 64),
        publishOptions: (any HAPublishOptionsStore)? = nil
    ) {
        self.slideshow = slideshow
        self.powerManager = powerManager
        self.albums = albums
        self.currentAlbumID = currentAlbumID
        self.sources = sources
        self.onSelectSource = onSelectSource
        self.isPhotoLibrarySource = isPhotoLibrarySource
        self.brightness = min(max(initialBrightness, 0), 1)
        self.currentAlbum = sources.first { $0.id == activeSourceID }?.label
            ?? albums.first { $0.id == currentAlbumID }?.name
        self.themeStore = themeStore
        self.api = api
        self.metadataCache = metadataCache
        self.publishOptions = publishOptions
        self._currentPhotoReport = PhotoReport(
            assetID: slideshow.currentAssetID,
            imageData: nil,
            takenAt: nil, city: nil, state: nil, country: nil,
            albumID: slideshow.albumID,
            albumName: albums.first { $0.id == slideshow.albumID }?.name,
            phase: Self.mapPhase(slideshow.phase),
            photoCount: albums.first { $0.id == slideshow.albumID }?.assetCount ?? 0
        )
        observeThemeSettings()
        observeCurrentPhoto()
        observePlayback()
    }

    // The chrome play/pause button calls `slideshow.togglePause()` directly, never
    // these methods — so a remote (HA) pause/resume must go through the same
    // `isPaused` flag the chrome uses (via `togglePause()`, guarded so it doesn't
    // flip the wrong way) rather than the ticker-only `slideshow.pause()/resume()`.
    // That way both origins update one source of truth, and `observePlayback()`
    // below is the single place that reports the change to HA.
    public func pause() {
        guard !slideshow.isPaused else { return }
        slideshow.togglePause()
    }

    public func resume() {
        guard slideshow.isPaused else { return }
        slideshow.togglePause()
    }

    public func setBrightness(_ value: Double) async {
        let clamped = min(max(value, 0), 1)
        brightness = clamped
        await powerManager.setBrightness(clamped, animated: true)
    }

    /// The album list arrives after init (800): the adapter is built synchronously at
    /// the slideshow composition point, and the HA coordinator's best-effort `albums()`
    /// fetch lands here later. With a source library the sources keep owning the select
    /// options and the current label; the album list then only enriches photo reports.
    public func updateAlbums(_ albums: [Album]) {
        self.albums = albums
        if sources.isEmpty, currentAlbum == nil {
            currentAlbum = albums.first { $0.id == currentAlbumID }?.name
        }
    }

    public func selectAlbum(_ name: String) {
        // 900 (FR-900-11): with a source library, the option is a source LABEL and the
        // switch goes through the app (it owns the cross-backend rebuild strategy).
        // An unknown option changes nothing either way (FR-700-14 semantics).
        if !sources.isEmpty {
            guard let source = sources.first(where: { $0.label == name }) else { return }
            currentAlbum = name
            onSelectSource?(source.id)
            onLocalChange?()
            return
        }
        guard let album = albums.first(where: { $0.name == name }) else { return }
        currentAlbum = name
        Task { await slideshow.switchAlbum(album.id) }
        onLocalChange?()
    }

    // MARK: - Settings observation

    /// Re-armed observation of the theme store. `onChange` fires synchronously at
    /// willSet on the main actor, so the suppress flag must be read THERE — a
    /// remote `apply(_:)` resets it before any deferred task would run.
    private func observeThemeSettings() {
        guard let themeStore else { return }
        withObservationTracking {
            _ = themeStore.settings
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let suppressed = self.suppressSettingsCallback
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.observeThemeSettings()
                    if !suppressed {
                        self.onSettingsChange?()
                    }
                }
            }
        }
    }

    /// Re-armed observation of `slideshow.isPaused` — the single source of truth for
    /// `playbackState` — so a chrome-driven pause (which never calls `pause()`/
    /// `resume()` above) still reaches HA (FR-710-12/20).
    private func observePlayback() {
        withObservationTracking {
            _ = slideshow.isPaused
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.observePlayback()
                    self.onLocalChange?()
                }
            }
        }
    }

    // MARK: - Photo reporting (US2)

    /// Re-armed observation of the running slideshow's current asset + phase. Like
    /// `observeThemeSettings`, `onChange` fires at willSet on the main actor; the
    /// actual (async) report build is deferred to a task so the slide advance that
    /// triggered it returns immediately — no added transition delay (SC-710-04).
    private func observeCurrentPhoto() {
        withObservationTracking {
            _ = slideshow.currentAssetID
            _ = slideshow.phase
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.observeCurrentPhoto()
                    await self.rebuildPhotoReport()
                }
            }
        }
    }

    private func rebuildPhotoReport() async {
        let report = await buildPhotoReport()
        _currentPhotoReport = report
        onPhotoChange?(report)
    }

    private func buildPhotoReport() async -> PhotoReport {
        let assetID = slideshow.currentAssetID
        let albumID = slideshow.albumID
        // For a Photos source the server album list can't know the collection — the
        // active source's label (mirrored in currentAlbum) names it instead (900).
        let albumName = albums.first { $0.id == albumID }?.name
            ?? (isPhotoLibrarySource ? currentAlbum : nil)
        let phase = Self.mapPhase(slideshow.phase)
        let count = albumPhotoCount(albumID)

        guard let assetID else {
            return PhotoReport(
                assetID: nil, imageData: nil,
                takenAt: nil, city: nil, state: nil, country: nil,
                albumID: albumID, albumName: albumName,
                phase: phase, photoCount: count
            )
        }

        // 900 (FR-900-11/12): a Photos source publishes through the engine's neutral
        // pass-throughs — capture date only, no place fields (R7, no geocoding); image
        // bytes under the same global opt-in. Immich keeps its richer EXIF path.
        let meta: CachedMetadata?
        let image: Data?
        if isPhotoLibrarySource {
            meta = await neutralMetadata(for: assetID)
            image = await neutralImageData(for: assetID)
        } else if let api {
            meta = await metadata(for: assetID, api: api)
            image = await imageData(for: assetID, api: api)
        } else {
            meta = nil
            image = nil
        }

        return PhotoReport(
            assetID: assetID, imageData: image,
            takenAt: meta?.takenAt, city: meta?.city, state: meta?.state, country: meta?.country,
            albumID: albumID, albumName: albumName,
            phase: phase, photoCount: count
        )
    }

    /// Photo count for the `photo_count` diagnostic sensor (FR-710-07): the active
    /// album's asset count as reported by Immich, or — when the album isn't in the
    /// (best-effort) list, e.g. any Photos collection — the engine's own loaded
    /// rotation size (900).
    private func albumPhotoCount(_ albumID: String) -> Int {
        albums.first { $0.id == albumID }?.assetCount ?? slideshow.photoCount
    }

    /// Metadata via the bounded LRU cache; a fetch failure yields `nil` (never
    /// cached) but the asset ID is still reported.
    private func metadata(for assetID: String, api: any ImmichAPI) async -> CachedMetadata? {
        if let cached = metadataCache.metadata(for: assetID) {
            return cached
        }
        do {
            let info = try await api.assetInfo(assetID: assetID)
            let meta = CachedMetadata(
                takenAt: info.takenAt, city: info.city, state: info.state, country: info.country
            )
            metadataCache.store(meta, for: assetID)
            return meta
        } catch {
            return nil
        }
    }

    /// Neutral metadata for a Photos-backed show (900, R7): the capture date through the
    /// engine's pass-through; place fields stay empty — no geocoding. Same bounded cache.
    private func neutralMetadata(for assetID: String) async -> CachedMetadata? {
        if let cached = metadataCache.metadata(for: assetID) {
            return cached
        }
        guard let metadata = try? await slideshow.metadata(for: assetID) else { return nil }
        let meta = CachedMetadata(takenAt: metadata.capturedAt, city: nil, state: nil, country: nil)
        metadataCache.store(meta, for: assetID)
        return meta
    }

    /// Image bytes for a Photos-backed show (900, FR-900-12): the same global opt-in and
    /// byte cap as Immich, fetched through the engine's neutral pass-through.
    private func neutralImageData(for assetID: String) async -> Data? {
        let options = publishOptions?.options ?? HAPublishOptions()
        guard options.imageEnabled else { return nil }
        let fidelity: ImageFidelity = options.imageSource == .thumbnail ? .thumbnail : .preview
        guard let raw = try? await slideshow.imageData(for: assetID, fidelity: fidelity) else { return nil }
        return Self.downscaledJPEG(from: raw, cap: options.byteCap)
    }

    /// Image bytes for HA: only when publishing images is enabled; fetched via the
    /// configured source, then downscaled/capped to the byte budget. `nil` when
    /// disabled, on a fetch failure, or if it can't be brought under the cap.
    private func imageData(for assetID: String, api: any ImmichAPI) async -> Data? {
        let options = publishOptions?.options ?? HAPublishOptions()
        guard options.imageEnabled else { return nil }
        do {
            let raw: Data
            switch options.imageSource {
            case .thumbnail: raw = try await api.thumbnail(assetID: assetID)
            case .preview: raw = try await api.preview(assetID: assetID)
            }
            return Self.downscaledJPEG(from: raw, cap: options.byteCap)
        } catch {
            return nil
        }
    }

    private static func mapPhase(_ phase: SlideshowPhase) -> SlideshowPhaseReport {
        switch phase {
        case .loading: return .loading
        case .playing: return .playing
        case .empty: return .empty
        case .failed: return .failed
        }
    }

    /// Re-encode to JPEG under `cap` bytes, first dropping quality then shrinking
    /// dimensions. Returns `nil` if the image can't be decoded or never fits.
    private static func downscaledJPEG(from data: Data, cap: Int) -> Data? {
        guard cap > 0, let image = UIImage(data: data) else { return nil }
        var current = image
        var quality: CGFloat = 0.85
        for _ in 0..<8 {
            if let jpeg = current.jpegData(compressionQuality: quality), jpeg.count <= cap {
                return jpeg
            }
            if quality > 0.35 {
                quality -= 0.2
            } else {
                let scaled = current.scaled(by: 0.7)
                guard scaled.size.width >= 1, scaled.size.height >= 1 else { return nil }
                current = scaled
                quality = 0.7
            }
        }
        return nil
    }
}

// MARK: - PhotoReporting

extension SlideshowRemoteControlAdapter: PhotoReporting {
    public var currentPhotoReport: PhotoReport { _currentPhotoReport }

    public var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    public func showNext() async {
        await slideshow.showNext()
    }

    public func showPrevious() async {
        await slideshow.showPrevious()
    }
}

private extension UIImage {
    func scaled(by factor: CGFloat) -> UIImage {
        let newSize = CGSize(width: size.width * factor, height: size.height * factor)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - SettingsControlling

extension SlideshowRemoteControlAdapter: SettingsControlling {
    public var themeSettings: ThemeSettingsSnapshot {
        Self.snapshot(from: themeStore?.settings ?? ThemeSettings())
    }

    public func apply(_ settings: ThemeSettingsSnapshot) {
        guard let themeStore else { return }
        suppressSettingsCallback = true
        defer { suppressSettingsCallback = false }
        themeStore.settings = Self.themeSettings(from: settings)
    }

    // The 11-field mapping bridges via raw values so HAControlKit stays free of a
    // ThemeKit dependency (Modular Isolation); the fallbacks are unreachable as
    // long as both enums list identical cases.
    private static func snapshot(from settings: ThemeSettings) -> ThemeSettingsSnapshot {
        ThemeSettingsSnapshot(
            order: PlayOrderSetting(rawValue: settings.order.rawValue) ?? .shuffle,
            durationSeconds: Int(settings.duration.components.seconds),
            transition: TransitionSetting(rawValue: settings.transition.rawValue) ?? .crossfade,
            kenBurns: settings.kenBurns,
            fit: FitSetting(rawValue: settings.fit.rawValue) ?? .fit,
            quality: QualitySetting(rawValue: settings.quality.rawValue) ?? .preview,
            clockOn: settings.clock.isOn,
            clockPlace: ClockCornerSetting(rawValue: settings.clock.place.rawValue) ?? .bottomTrailing,
            clockStyle: ClockStyleSetting(rawValue: settings.clock.style.rawValue) ?? .digits,
            clockSize: ClockSizeSetting(rawValue: settings.clock.size.rawValue) ?? .room,
            clockDate: settings.clock.showDate
        )
    }

    private static func themeSettings(from snapshot: ThemeSettingsSnapshot) -> ThemeSettings {
        ThemeSettings(
            order: PlayOrder(rawValue: snapshot.order.rawValue) ?? .shuffle,
            duration: .seconds(snapshot.durationSeconds),
            transition: Transition(rawValue: snapshot.transition.rawValue) ?? .crossfade,
            kenBurns: snapshot.kenBurns,
            fit: ImageFit(rawValue: snapshot.fit.rawValue) ?? .fit,
            quality: ImageQuality(rawValue: snapshot.quality.rawValue) ?? .preview,
            clock: ClockSettings(
                isOn: snapshot.clockOn,
                style: ClockStyle(rawValue: snapshot.clockStyle.rawValue) ?? .digits,
                place: ClockPlace(rawValue: snapshot.clockPlace.rawValue) ?? .bottomTrailing,
                size: ClockSize(rawValue: snapshot.clockSize.rawValue) ?? .room,
                showDate: snapshot.clockDate
            )
        )
    }
}

//
//  SlideshowRemoteControlAdapter.swift
//  Immich Slideshow
//

import HAControlKit
import ImmichClient
import PowerKit
import SlideshowKit

/// Bridges Home-Assistant remote control onto the running app: pause/play onto the
/// `SlideshowViewModel`, brightness onto the foreground-gated `PowerManager`, and
/// album selection onto the slideshow's runtime album switch.
@MainActor
public final class SlideshowRemoteControlAdapter: PlaybackControlling {
    private let slideshow: SlideshowViewModel
    private let powerManager: PowerManager
    private let albums: [Album]

    public private(set) var playbackState: PlaybackState = .playing
    // Current target brightness (0.0–1.0). The PowerManager itself owns the actual
    // screen and only applies it in the foreground (Konstitution V); we mirror the
    // requested target so HA echoes a stable value.
    public private(set) var brightness: Double
    public var albumOptions: [String] { albums.map(\.name) }
    public private(set) var currentAlbum: String?
    public var onLocalChange: (@MainActor () -> Void)?

    public init(
        slideshow: SlideshowViewModel,
        powerManager: PowerManager,
        albums: [Album] = [],
        currentAlbumID: String? = nil,
        initialBrightness: Double = 1.0
    ) {
        self.slideshow = slideshow
        self.powerManager = powerManager
        self.albums = albums
        self.brightness = min(max(initialBrightness, 0), 1)
        self.currentAlbum = albums.first { $0.id == currentAlbumID }?.name
    }

    public func pause() {
        slideshow.pause()
        playbackState = .paused
        onLocalChange?()
    }

    public func resume() {
        slideshow.resume()
        playbackState = .playing
        onLocalChange?()
    }

    public func setBrightness(_ value: Double) async {
        let clamped = min(max(value, 0), 1)
        brightness = clamped
        await powerManager.setBrightness(clamped, animated: true)
    }

    public func selectAlbum(_ name: String) {
        guard let album = albums.first(where: { $0.name == name }) else { return }
        currentAlbum = name
        Task { await slideshow.switchAlbum(album.id) }
        onLocalChange?()
    }
}

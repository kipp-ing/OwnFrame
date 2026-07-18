//
//  ImmichSlideshowTVApp.swift
//  Immich SlideshowTV
//
//  Topic 1000 (US1) — the tvOS composition root. Builds the shared engine + power/screen
//  stack once and hands it to the tvOS slideshow host. The source is currently the local
//  `TVStubPhotoSource` (simulator has no configured server); T011/onboarding will replace it
//  with the real Immich/Photos source injected into the same `SlideshowViewModel` seam,
//  without changing the rest of this graph.
//

import PowerKit
import SlideshowKit
import SwiftUI
import ThemeKit

@main
struct ImmichSlideshowTVApp: App {
    @State private var composition = TVComposition()

    var body: some Scene {
        WindowGroup {
            TVSlideshowView(
                viewModel: composition.viewModel,
                screen: composition.screen,
                powerManager: composition.powerManager,
                themeStore: composition.themeStore
            )
        }
    }
}

/// Built-once object graph for the tvOS app. Held in `@State` so it survives view updates;
/// its members are the `@Observable` engine/power/screen/theme objects that drive the UI.
@MainActor
final class TVComposition {
    let themeStore: UserDefaultsThemeStore
    let screen: SoftwareDimScreenController
    let powerManager: PowerManager
    let viewModel: SlideshowViewModel

    init() {
        let themeStore = UserDefaultsThemeStore()
        let screen = SoftwareDimScreenController()
        self.themeStore = themeStore
        self.screen = screen
        self.powerManager = PowerManager(screen: screen)
        // TODO(T011/onboarding): replace TVStubPhotoSource() with the configured real source
        // (Immich album / Photos) and the selected collection id.
        self.viewModel = SlideshowViewModel(
            source: TVStubPhotoSource(),
            collectionID: "stub",
            ticker: RealTicker(),
            settingsStore: themeStore
        )
    }
}

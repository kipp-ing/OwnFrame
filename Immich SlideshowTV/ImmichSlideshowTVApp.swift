import SwiftUI

// tvOS app entry (topic 1000). This stub proves the target builds and links the shared
// packages for a tvOS destination; the real composition root (engine + software-dim screen
// controller + distinct HA identity + onboarding routing) replaces the body in T011.
@main
struct ImmichSlideshowTVApp: App {
    var body: some Scene {
        WindowGroup {
            TVRootPlaceholderView()
        }
    }
}

struct TVRootPlaceholderView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text("Photo Frame — Apple TV")
                .font(.largeTitle)
                .foregroundStyle(.white)
        }
    }
}

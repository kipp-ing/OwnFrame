//
//  NewPhotosOverlayView.swift
//  OwnFrame
//
//  The optional "new photos arrived" card (310, FR-310-14 extends the periodic-refresh
//  spec; depicted by 9010 store slot 5). Pure ambience like the clock overlay: never
//  interactive, gone from the tree whenever the chrome is up. Keyed on the refresh's
//  `NewArrival.id` (not just its count) so a repeat arrival with the same count still
//  re-shows and re-starts its own fade timer. Off by default
//  (`ThemeSettings.newPhotosCard`) and free — an undisturbed picture is the product's
//  whole value, so this is opt-in, never gated (9010, FR-9010-07 only binds Ken Burns
//  and the clock overlay).
//

import SlideshowKit
import SwiftUI

struct NewPhotosOverlayView: View {
    let arrival: SlideshowViewModel.NewArrival?
    /// The active source's own display name (e.g. "Family"), never a `SourceKind`
    /// category word — sidesteps both the "Shared Album" vocabulary trap and the
    /// hostname-leak trap a kind subtitle carries (`SourceLibraryView.swift:321`).
    let sourceLabel: String?
    let chromeVisible: Bool

    @State private var visible = false

    private static let displayDuration: Duration = .seconds(5)

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            if visible, !chromeVisible, let arrival {
                card(for: arrival)
                    // Chrome-parity insets (FR-300-33), same as the clock overlay.
                    .padding(.horizontal, 32)
                    .padding(.vertical, 44)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("slideshow.newPhotosCard")
                    .accessibilityValue(countLabel(arrival.count))
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.3), value: visible)
        .animation(.easeInOut(duration: 0.3), value: chromeVisible)
        // Keyed on the arrival's id: a fresh arrival (even a repeat count) restarts the
        // task, which re-shows the card and re-arms its own fade-out.
        .task(id: arrival?.id) {
            guard arrival != nil else {
                visible = false
                return
            }
            visible = true
            try? await Task.sleep(for: Self.displayDuration)
            guard !Task.isCancelled else { return }
            visible = false
        }
    }

    @ViewBuilder
    private func card(for arrival: SlideshowViewModel.NewArrival) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let sourceLabel {
                Text(sourceLabel)
                    .font(.headline)
            }
            Text(countLabel(arrival.count))
                .font(.title3.weight(.semibold))
            // FR-9010-06/FR-310-06: a fixed 60-minute foreground-only re-fetch — "automatic"
            // is fair, nothing here may imply instant or background arrival.
            Text("Updated automatically")
                .font(.footnote)
                .opacity(0.75)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.35), radius: 6, y: 1)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .glassCard(cornerRadius: 20)
    }

    private func countLabel(_ count: Int) -> String {
        count == 1 ? String(localized: "+1 new photo") : String(localized: "+\(count) new photos")
    }
}

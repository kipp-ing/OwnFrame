//
//  SlideshowEmptyView.swift
//  OwnFrame
//
//  Calm hint shown when the selected album has no displayable images (FR-009).
//

import SwiftUI

struct SlideshowEmptyView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle")
                .imageScale(.large)
                .foregroundStyle(.secondary)
            Text("No images in this album")
                .font(.headline)
                .accessibilityIdentifier("slideshow.empty")
            Text("Pick an album with photos to start the slideshow.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .foregroundStyle(.white)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        SlideshowEmptyView()
    }
}

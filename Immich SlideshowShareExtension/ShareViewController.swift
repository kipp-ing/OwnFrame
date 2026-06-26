//
//  ShareViewController.swift
//  Immich SlideshowShareExtension
//
//  210, US2 — the iOS Share Sheet entry point. Deliberately thin (Constitution III/V):
//  extract the shared URL, hand it to the host app via the App Group (the non-secret URL
//  only — never a password or API key), best-effort wake the host, then return. No network,
//  no UI, no secret. The host (RootView.consumePendingLink) resolves/activates it on launch
//  or next foreground via OnboardingKit's IncomingSharedLink + the two-phase resolve engine.
//
//  The URL extraction here mirrors OnboardingKit's host-tested `ShareLinkExtraction`, and the
//  App-Group suite/key mirror `AppGroupPendingSharedLinkStore`. They are intentionally
//  duplicated (not linked) to keep the extension thin and free of app-extension link
//  constraints; keep the two constants below in sync with OnboardingKit if they ever change.
//

import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    /// Must match `AppGroupPendingSharedLinkStore.defaultSuiteName` / `.pendingURLKey` (OnboardingKit).
    private static let appGroupID = "group.ing.kipp.Immich-Slideshow"
    private static let pendingURLKey = "pendingSharedLinkURL"
    /// Best-effort wake of the host; takes effect once the `immichslideshow` scheme is
    /// registered on the host (otherwise the host picks the link up on next foreground).
    private static let hostScheme = "immichslideshow://shared"

    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await handleShare() }
    }

    private func handleShare() async {
        defer { extensionContext?.completeRequest(returningItems: nil, completionHandler: nil) }
        guard let url = await extractURL() else { return }
        UserDefaults(suiteName: Self.appGroupID)?.set(url.absoluteString, forKey: Self.pendingURLKey)
        openHost()
    }

    /// The first attachment that yields a URL: a `public.url` attachment, else a plain-text
    /// attachment whose trimmed string is an https URL.
    private func extractURL() async -> URL? {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []

        for item in items {
            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                if let loaded = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier),
                   let url = loaded as? URL {
                    return url
                }
            }
        }

        for item in items {
            for provider in item.attachments ?? [] where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                if let loaded = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier),
                   let text = loaded as? String,
                   let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                   url.scheme == "https" {
                    return url
                }
            }
        }

        return nil
    }

    private func openHost() {
        guard let url = URL(string: Self.hostScheme) else { return }
        extensionContext?.open(url, completionHandler: nil)
    }
}

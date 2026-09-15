//
//  ShareViewController.swift
//  OwnFrameShareExtension
//
//  210, US2 — the iOS Share Sheet entry point. Deliberately thin (Constitution III/V):
//  extract the shared URL, hand it to the host app via the App Group (the non-secret URL
//  only — never a password or API key), then say what happens next. A Share extension cannot
//  bring its host app forward on iOS, so it doesn't try: it shows "Open OwnFrame to start" and
//  closes when the person taps Done (FR-210-31). No network, no secret. The host
//  (RootView.consumePendingLink) resolves/activates the link on launch or on its next return to
//  the foreground (SC-210-02) via OnboardingKit's IncomingSharedLink + the two-phase resolve engine.
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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        Task { await handleShare() }
    }

    private func handleShare() async {
        guard let url = await extractURL() else {
            complete()
            return
        }
        UserDefaults(suiteName: Self.appGroupID)?.set(url.absoluteString, forKey: Self.pendingURLKey)
        showConfirmation()
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

    /// FR-210-31: the link is saved; tell the person to open OwnFrame, and close only on Done so
    /// the message can be read at their own pace.
    private func showConfirmation() {
        let message = UILabel()
        message.text = String(localized: "Open OwnFrame to start")
        message.font = .preferredFont(forTextStyle: .title2)
        message.adjustsFontForContentSizeCategory = true
        message.numberOfLines = 0
        message.textAlignment = .center
        message.accessibilityIdentifier = "share.confirmation.message"

        let done = UIButton(
            configuration: .filled(),
            primaryAction: UIAction(title: String(localized: "Done")) { [weak self] _ in self?.complete() }
        )
        done.accessibilityIdentifier = "share.confirmation.done"

        let stack = UIStackView(arrangedSubviews: [message, done])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}

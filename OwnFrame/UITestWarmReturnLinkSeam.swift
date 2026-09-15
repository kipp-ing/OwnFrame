//
//  UITestWarmReturnLinkSeam.swift
//  OwnFrame
//
//  210 T061 (#65, SC-210-02) warm-return seam, DEBUG only. The Share Extension can't bring
//  OwnFrame forward (FR-210-31), so a link shared while OwnFrame is running must be picked up
//  when the person switches back. `--uitest-pending-link-after-background <url>` puts the link
//  into the pending store only once the app has entered the background, as the extension would
//  while the person is in Safari, so a UI test proves the pickup happens on the return to the
//  foreground rather than at launch. Delivers once.
//

#if DEBUG
import Foundation
import OnboardingKit
import UIKit

nonisolated final class UITestWarmReturnLinkSeam: @unchecked Sendable {
    private static let flag = "--uitest-pending-link-after-background"
    /// The seam armed for this UI-test process; it must outlive the launch path that armed it.
    private nonisolated(unsafe) static var armed: UITestWarmReturnLinkSeam?

    private let lock = NSLock()
    private var delivered = false
    private let center: NotificationCenter
    private var observer: NSObjectProtocol?

    @MainActor
    init(link: URL, store: any PendingSharedLinkStore, center: NotificationCenter = .default) {
        self.center = center
        observer = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self, self.claimDelivery() else { return }
            store.savePendingURL(link)
        }
    }

    deinit {
        if let observer { center.removeObserver(observer) }
    }

    /// Arms the seam for this process when the launch arguments carry the flag.
    @MainActor
    static func arm(arguments: [String], store: any PendingSharedLinkStore) {
        guard let link = link(from: arguments) else { return }
        armed = UITestWarmReturnLinkSeam(link: link, store: store)
    }

    /// The URL following the flag, or nil when the flag is absent.
    static func link(from arguments: [String]) -> URL? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return URL(string: arguments[index + 1])
    }

    private func claimDelivery() -> Bool {
        lock.withLock {
            defer { delivered = true }
            return !delivered
        }
    }
}
#endif

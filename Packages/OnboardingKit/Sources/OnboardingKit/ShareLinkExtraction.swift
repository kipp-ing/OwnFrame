import Foundation
import UniformTypeIdentifiers

public enum ShareLinkExtraction: Sendable {
    public static func url(from items: [NSExtensionItem]) async -> URL? {
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = await loadURL(from: provider) {
                    return url
                }
            }
        }

        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let url = await loadHTTPSURLString(from: provider, typeIdentifier: UTType.plainText.identifier) {
                    return url
                }

                if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier),
                   let url = await loadHTTPSURLString(from: provider, typeIdentifier: UTType.text.identifier) {
                    return url
                }
            }
        }

        return nil
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        let item = await loadItem(from: provider, typeIdentifier: UTType.url.identifier)
        if case let .url(url) = item {
            return url
        }
        if case let .string(string) = item {
            return URL(string: string)
        }
        if case let .data(data) = item,
           let string = String(data: data, encoding: .utf8) {
            return URL(string: string)
        }
        return nil
    }

    private static func loadHTTPSURLString(from provider: NSItemProvider, typeIdentifier: String) async -> URL? {
        let item = await loadItem(from: provider, typeIdentifier: typeIdentifier)
        let string: String?
        if case let .string(loaded) = item {
            string = loaded
        } else if case let .data(data) = item {
            string = String(data: data, encoding: .utf8)
        } else {
            string = nil
        }

        guard
            let string,
            let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
            url.scheme == "https"
        else {
            return nil
        }

        return url
    }

    private static func loadItem(from provider: NSItemProvider, typeIdentifier: String) async -> LoadedItem? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                continuation.resume(returning: LoadedItem(item))
            }
        }
    }

    private enum LoadedItem: Sendable {
        case url(URL)
        case string(String)
        case data(Data)

        init?(_ item: NSSecureCoding?) {
            if let url = item as? URL {
                self = .url(url)
            } else if let url = item as? NSURL {
                self = .url(url as URL)
            } else if let string = item as? String {
                self = .string(string)
            } else if let string = item as? NSString {
                self = .string(string as String)
            } else if let data = item as? Data {
                self = .data(data)
            } else {
                return nil
            }
        }
    }
}

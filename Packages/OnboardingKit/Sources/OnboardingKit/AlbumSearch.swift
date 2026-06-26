import Foundation
import ImmichClient

public enum AlbumSearch: Sendable {
    public static func filter(_ albums: [Album], query: String) -> [Album] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else {
            return albums
        }

        let needle = folded(trimmedQuery)
        return albums.filter { album in
            folded(haystack(for: album)).contains(needle)
        }
    }

    private static func haystack(for album: Album) -> String {
        var tokens = [album.name]

        tokens.append(contentsOf: yearTokens(for: album))

        if let assetCount = album.assetCount {
            tokens.append("\(assetCount)")
        }

        return tokens.joined(separator: " ")
    }

    private static func yearTokens(for album: Album) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        var years: [Int] = []
        for date in [album.startDate, album.endDate].compactMap(\.self) {
            let year = calendar.component(.year, from: date)
            if years.contains(year) == false {
                years.append(year)
            }
        }

        return years.map(String.init)
    }

    private static func folded(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

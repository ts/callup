import Foundation

public struct LibrarySettings: Codable, Equatable, Sendable {
    public var televisionRoot: String?
    public var movieRoot: String?

    public init(televisionRoot: String? = nil, movieRoot: String? = nil) {
        self.televisionRoot = televisionRoot
        self.movieRoot = movieRoot
    }
}

public struct LibrarySnapshot: Sendable {
    private let televisionFiles: [LibraryFile]
    private let movieFiles: [LibraryFile]

    init(televisionFiles: [LibraryFile], movieFiles: [LibraryFile]) {
        self.televisionFiles = televisionFiles
        self.movieFiles = movieFiles
    }

    public func contains(_ movie: Movie) -> Bool {
        movieFiles.contains { $0.matches(movie: movie) }
    }

    public func episodeIDsOnDisk(
        for series: TelevisionSeries,
        episodes: [TelevisionEpisode]
    ) -> Set<ProviderReference> {
        Set(episodes.compactMap { episode in
            televisionFiles.contains { $0.matches(series: series, episode: episode) }
                ? episode.id : nil
        })
    }
}

public actor LibraryInventory {
    private struct Cache: Sendable {
        let settings: LibrarySettings
        let snapshot: LibrarySnapshot
        let scannedAt: Date
    }

    private var cache: Cache?
    private let cacheLifetime: TimeInterval

    public init(cacheLifetime: TimeInterval = 60) {
        self.cacheLifetime = cacheLifetime
    }

    public func snapshot(for settings: LibrarySettings, force: Bool = false) -> LibrarySnapshot {
        if !force,
           let cache,
           cache.settings == settings,
           Date().timeIntervalSince(cache.scannedAt) < cacheLifetime {
            return cache.snapshot
        }

        let snapshot = LibrarySnapshot(
            televisionFiles: scan(root: settings.televisionRoot),
            movieFiles: scan(root: settings.movieRoot)
        )
        cache = Cache(settings: settings, snapshot: snapshot, scannedAt: Date())
        return snapshot
    }

    public func invalidate() {
        cache = nil
    }

    private func scan(root: String?) -> [LibraryFile] {
        guard let root,
              !root.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        let url = URL(fileURLWithPath: root)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isHiddenKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var files: [LibraryFile] = []
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  LibraryFile.videoExtensions.contains(fileURL.pathExtension.lowercased()) else {
                continue
            }
            files.append(LibraryFile(url: fileURL, root: url))
        }
        return files
    }
}

struct LibraryFile: Sendable {
    static let videoExtensions: Set<String> = ["mkv", "mp4", "m4v", "avi", "mov", "wmv", "ts"]

    let components: [[String]]
    let filename: [String]

    init(url: URL, root: URL) {
        let relative = String(url.path.dropFirst(root.path.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let names = relative.split(separator: "/").map(String.init)
        components = names.map { Self.tokens(for: $0) }
        filename = Self.tokens(for: url.deletingPathExtension().lastPathComponent)
    }

    func matches(movie: Movie) -> Bool {
        let title = Self.tokens(for: movie.title)
        guard !title.isEmpty else { return false }
        return components.contains { component in
            guard let index = component.firstRange(of: title) else { return false }
            let following = component.dropFirst(index + title.count).first
            guard following == nil || Self.isMovieSuffix(following!) else { return false }
            if let year = movie.releaseYear,
               let foundYear = component.first(where: Self.isYear),
               foundYear != String(year) {
                return false
            }
            return true
        }
    }

    func matches(series: TelevisionSeries, episode: TelevisionEpisode) -> Bool {
        let seriesTitle = Self.tokens(for: series.title)
        guard !seriesTitle.isEmpty,
              components.dropLast().contains(where: { Self.matchesTitle(seriesTitle, in: $0) }),
              let number = episode.episodeNumber else {
            return false
        }
        let joined = filename.joined(separator: " ")
        let patterns = [
            #"\bs0*(\d{1,2})\s*e0*(\d{1,3})\b"#,
            #"\b0*(\d{1,2})\s*x\s*0*(\d{1,3})\b"#,
        ]
        return patterns.contains { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(
                    in: joined,
                    range: NSRange(joined.startIndex..., in: joined)
                  ),
                  let seasonRange = Range(match.range(at: 1), in: joined),
                  let episodeRange = Range(match.range(at: 2), in: joined) else {
                return false
            }
            return Int(joined[seasonRange]) == episode.seasonNumber
                && Int(joined[episodeRange]) == number
        }
    }

    private static func tokens(for value: String) -> [String] {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    private static func isYear(_ token: String) -> Bool {
        token.count == 4 && Int(token).map { (1900...2100).contains($0) } == true
    }

    private static func isMovieSuffix(_ token: String) -> Bool {
        isYear(token) || ["480p", "576p", "720p", "1080p", "2160p", "4k", "bluray", "web", "webrip", "webdl", "hdtv", "remux", "x264", "x265", "hevc", "avc", "av1"].contains(token)
    }

    private static func matchesTitle(_ title: [String], in component: [String]) -> Bool {
        guard let index = component.firstRange(of: title) else { return false }
        let following = component.dropFirst(index + title.count)
        return following.isEmpty || following.allSatisfy(isYear)
    }
}

private extension Array where Element == String {
    func firstRange(of needle: [String]) -> Int? {
        guard count >= needle.count else { return nil }
        return indices.first { start in
            let end = index(start, offsetBy: needle.count, limitedBy: endIndex) ?? endIndex
            return Array(self[start..<end]) == needle
        }
    }
}

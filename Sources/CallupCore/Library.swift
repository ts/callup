import Foundation

public struct LibrarySettings: Codable, Equatable, Sendable {
    public var televisionRoot: String?
    public var movieRoot: String?

    public init(televisionRoot: String? = nil, movieRoot: String? = nil) {
        self.televisionRoot = televisionRoot
        self.movieRoot = movieRoot
    }
}

public struct LibraryFileDetails: Codable, Equatable, Sendable {
    public let name: String
    public let relativePath: String
    public let sizeBytes: Int64?
    public let modifiedAt: Date?
    public let inferredTraits: ReportedReleaseTraits

    public init(
        name: String,
        relativePath: String,
        sizeBytes: Int64?,
        modifiedAt: Date?,
        inferredTraits: ReportedReleaseTraits
    ) {
        self.name = name
        self.relativePath = relativePath
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.inferredTraits = inferredTraits
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
        !filesOnDisk(for: movie).isEmpty
    }

    public func filesOnDisk(for movie: Movie) -> [LibraryFileDetails] {
        movieFiles.filter { $0.matches(movie: movie) }.map(\.details).sorted {
            $0.relativePath < $1.relativePath
        }
    }

    public func episodeIDsOnDisk(
        for series: TelevisionSeries,
        episodes: [TelevisionEpisode]
    ) -> Set<ProviderReference> {
        Set(episodeFilesOnDisk(for: series, episodes: episodes).keys)
    }

    public func episodeFilesOnDisk(
        for series: TelevisionSeries,
        episodes: [TelevisionEpisode]
    ) -> [ProviderReference: [LibraryFileDetails]] {
        Dictionary(uniqueKeysWithValues: episodes.compactMap { episode in
            let matches = televisionFiles
                .filter { $0.matches(series: series, episode: episode) }
                .map(\.details)
                .sorted { $0.relativePath < $1.relativePath }
            return matches.isEmpty ? nil : (episode.id, matches)
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
        let url = URL(fileURLWithPath: root).resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isHiddenKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ]
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
            files.append(LibraryFile(
                url: fileURL,
                root: url,
                sizeBytes: values.fileSize.map(Int64.init),
                modifiedAt: values.contentModificationDate
            ))
        }
        return files
    }
}

struct LibraryFile: Sendable {
    static let videoExtensions: Set<String> = ["mkv", "mp4", "m4v", "avi", "mov", "wmv", "ts"]

    let components: [[String]]
    let filename: [String]
    let name: String
    let relativePath: String
    let sizeBytes: Int64?
    let modifiedAt: Date?

    var details: LibraryFileDetails {
        LibraryFileDetails(
            name: name,
            relativePath: relativePath,
            sizeBytes: sizeBytes,
            modifiedAt: modifiedAt,
            inferredTraits: .inferred(from: name)
        )
    }

    init(url: URL, root: URL, sizeBytes: Int64?, modifiedAt: Date?) {
        let rootComponents = root.resolvingSymlinksInPath().pathComponents
        let fileComponents = url.resolvingSymlinksInPath().pathComponents
        let names = fileComponents.starts(with: rootComponents)
            ? Array(fileComponents.dropFirst(rootComponents.count))
            : [url.lastPathComponent]
        let relative = names.joined(separator: "/")
        components = names.map { Self.tokens(for: $0) }
        filename = Self.tokens(for: url.deletingPathExtension().lastPathComponent)
        name = url.lastPathComponent
        relativePath = relative
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
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

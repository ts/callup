import CallupCore
import Foundation

struct ParsedReleaseTitle: Equatable {
    let coverage: [CandidateCoverage]
    let traits: ReportedReleaseTraits
}

enum ReleaseTitleParser {
    static func parse(_ title: String) -> ParsedReleaseTitle {
        ParsedReleaseTitle(
            coverage: parseCoverage(title),
            traits: ReportedReleaseTraits(
                videoCodec: firstToken(in: title, tokens: [
                    (#"(?i)(?<![A-Z0-9])(?:HEVC|H[ .]?265|X265)(?![A-Z0-9])"#, "HEVC"),
                    (#"(?i)(?<![A-Z0-9])(?:AVC|H[ .]?264|X264)(?![A-Z0-9])"#, "AVC"),
                    (#"(?i)(?<![A-Z0-9])AV1(?![A-Z0-9])"#, "AV1"),
                    (#"(?i)(?<![A-Z0-9])(?:MPEG[ .-]?2|MPEG2)(?![A-Z0-9])"#, "MPEG-2"),
                ]),
                resolution: firstToken(in: title, tokens: [
                    (#"(?i)(?<![A-Z0-9])(?:2160P|4K|UHD)(?![A-Z0-9])"#, "2160p"),
                    (#"(?i)(?<![A-Z0-9])1080P(?![A-Z0-9])"#, "1080p"),
                    (#"(?i)(?<![A-Z0-9])1080I(?![A-Z0-9])"#, "1080i"),
                    (#"(?i)(?<![A-Z0-9])720P(?![A-Z0-9])"#, "720p"),
                    (#"(?i)(?<![A-Z0-9])(?:576P|576I)(?![A-Z0-9])"#, "576p"),
                    (#"(?i)(?<![A-Z0-9])(?:480P|480I|SDTV)(?![A-Z0-9])"#, "480p"),
                ]),
                source: firstToken(in: title, tokens: [
                    (#"(?i)(?<![A-Z0-9])WEB[ ._-]?DL(?![A-Z0-9])"#, "WEB-DL"),
                    (#"(?i)(?<![A-Z0-9])WEB[ ._-]?RIP(?![A-Z0-9])"#, "WEBRip"),
                    (#"(?i)(?<![A-Z0-9])(?:BLU[ ._-]?RAY|BDRIP|BRRIP)(?![A-Z0-9])"#, "BluRay"),
                    (#"(?i)(?<![A-Z0-9])HDTV(?![A-Z0-9])"#, "HDTV"),
                    (#"(?i)(?<![A-Z0-9])DVD(?:RIP)?(?![A-Z0-9])"#, "DVD"),
                    (#"(?i)(?<![A-Z0-9])WEB(?![A-Z0-9])"#, "WEB"),
                ])
            )
        )
    }

    private static func parseCoverage(_ title: String) -> [CandidateCoverage] {
        if let values = captures(
            in: title,
            pattern: #"(?i)(?<![A-Z0-9])S(\d{1,2})[ ._-]*E(\d{1,3})[ ._-]*-[ ._-]*(?:S(\d{1,2})[ ._-]*)?E?(\d{1,3})(?!\d)"#
        ) {
            guard let season = Int(values[0]),
                  let firstEpisode = Int(values[1]),
                  Int(values[2]) == nil || Int(values[2]) == season,
                  let lastEpisode = Int(values[3]),
                  let episodes = episodeRange(from: firstEpisode, through: lastEpisode)
            else { return [] }
            return [episodeCoverage(season: season, episodes: episodes)]
        }

        if let values = captures(
            in: title,
            pattern: #"(?i)(?<![A-Z0-9])S(\d{1,2})((?:[ ._]*E\d{1,3})+)(?!\d)"#
        ),
           let season = Int(values[0]) {
            let episodes = allCaptures(in: values[1], pattern: #"(?i)E(\d{1,3})"#)
                .compactMap(Int.init)
            if !episodes.isEmpty {
                return [episodeCoverage(season: season, episodes: episodes)]
            }
        }

        if let values = captures(
            in: title,
            pattern: #"(?i)(?<![A-Z0-9])(\d{1,2})X(\d{1,3})(?:[ ._-]*-[ ._-]*(?:(\d{1,2})X)?(\d{1,3}))?(?!\d)"#
        ),
           let season = Int(values[0]),
           let firstEpisode = Int(values[1]) {
            let lastSeason = Int(values[2])
            let lastEpisode = Int(values[3])
            guard lastSeason == nil || lastSeason == season else { return [] }
            let episodes = lastEpisode.flatMap { episodeRange(from: firstEpisode, through: $0) }
                ?? [firstEpisode]
            return [episodeCoverage(season: season, episodes: episodes)]
        }

        if let values = captures(
            in: title,
            pattern: #"(?i)(?<![A-Z0-9])S(\d{1,2})(?![A-Z0-9]).{0,20}(?<![A-Z0-9])(?:COMPLETE|PACK)(?![A-Z0-9])"#
        ),
           let season = Int(values[0]) {
            return [.init(scope: .televisionSeason, seasonNumber: season)]
        }

        if let values = captures(
            in: title,
            pattern: #"(?i)(?<![A-Z0-9])SEASON[ ._-]*(\d{1,2}).{0,20}(?<![A-Z0-9])(?:COMPLETE|PACK)(?![A-Z0-9])"#
        ),
           let season = Int(values[0]) {
            return [.init(scope: .televisionSeason, seasonNumber: season)]
        }

        return []
    }

    private static func episodeCoverage(season: Int, episodes: [Int]) -> CandidateCoverage {
        .init(
            scope: .televisionEpisode,
            seasonNumber: season,
            episodeNumbers: Array(Set(episodes)).sorted()
        )
    }

    private static func episodeRange(from first: Int, through last: Int) -> [Int]? {
        guard first <= last, last - first < 200 else { return nil }
        return Array(first...last)
    }

    private static func firstToken(
        in title: String,
        tokens: [(pattern: String, value: String)]
    ) -> String? {
        tokens.first { matches(title, pattern: $0.pattern) }?.value
    }

    private static func matches(_ value: String, pattern: String) -> Bool {
        regex(pattern).firstMatch(
            in: value,
            range: NSRange(value.startIndex..., in: value)
        ) != nil
    }

    private static func captures(in value: String, pattern: String) -> [String]? {
        guard let match = regex(pattern).firstMatch(
            in: value,
            range: NSRange(value.startIndex..., in: value)
        ) else { return nil }

        return (1..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: value) else { return "" }
            return String(value[range])
        }
    }

    private static func allCaptures(in value: String, pattern: String) -> [String] {
        regex(pattern).matches(in: value, range: NSRange(value.startIndex..., in: value)).compactMap {
            guard let range = Range($0.range(at: 1), in: value) else { return nil }
            return String(value[range])
        }
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are constants covered by tests, so construction failure is a programmer error.
        try! NSRegularExpression(pattern: pattern)
    }
}

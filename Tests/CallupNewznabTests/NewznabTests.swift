import CallupCore
import Foundation
import Testing
@testable import CallupNewznab

@Test func buildsTVSearchAndRedactsCredential() throws {
    let key = try NewznabAPIKey("fixture-key")
    let url = try NewznabRequestBuilder.tvSearchURL(
        endpoint: #require(URL(string: "https://api.nzbgeek.info/api")),
        apiKey: key,
        search: NewznabTVSearch(
            query: "A Great Show",
            tvmazeID: "123",
            tvdbID: "456",
            imdbID: "tt789",
            season: 1,
            categories: [5030, 5040]
        )
    )
    let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    let values = Dictionary(uniqueKeysWithValues: query.compactMap { item in
        item.value.map { (item.name, $0) }
    })

    #expect(values["t"] == "tvsearch")
    #expect(values["apikey"] == "fixture-key")
    #expect(values["q"] == "A Great Show")
    #expect(values["tvmazeid"] == "123")
    #expect(values["tvdbid"] == "456")
    #expect(values["imdbid"] == "tt789")
    #expect(values["season"] == "1")
    #expect(values["cat"] == "5030,5040")
    #expect(values["extended"] == "1")
    #expect(key.description == "<redacted>")

    let description = NewznabRequestBuilder.redactedDescription(of: url)
    #expect(!description.contains("fixture-key"))
    #expect(description.contains("apikey=%3Credacted%3E"))
}

@Test func buildsCredentialedDownloadOnlyOnTheServer() throws {
    let key = try NewznabAPIKey("fixture-key")
    let url = try NewznabRequestBuilder.downloadURL(
        endpoint: #require(URL(string: "https://api.nzbgeek.info/api")),
        apiKey: key,
        identifier: "release-one"
    )
    let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    let values = Dictionary(uniqueKeysWithValues: query.compactMap { item in
        item.value.map { (item.name, $0) }
    })

    #expect(values["t"] == "get")
    #expect(values["id"] == "release-one")
    #expect(values["apikey"] == "fixture-key")
    #expect(!NewznabRequestBuilder.redactedDescription(of: url).contains("fixture-key"))
}

@Test func combinesReportedMetadataWithTraitsAndCoverageParsedFromTitles() throws {
    let fixture = try #require(
        Bundle.module.url(forResource: "tv-search", withExtension: "xml", subdirectory: "Fixtures")
    )
    let page = try NewznabResponseDecoder.decode(Data(contentsOf: fixture), provider: "nzbgeek")

    #expect(page.offset == 0)
    #expect(page.total == 3)
    #expect(page.candidates.count == 3)

    let episode = page.candidates[0]
    #expect(episode.id == ProviderReference(provider: "nzbgeek", value: "release-episode-1"))
    #expect(episode.sizeBytes == 734_003_200)
    #expect(episode.reportedTraits.videoCodec == "HEVC")
    #expect(episode.reportedTraits.resolution == "1920x1080")
    #expect(episode.reportedTraits.source == "WEB-DL")
    #expect(episode.coverage == [
        CandidateCoverage(scope: .televisionEpisode, seasonNumber: 1, episodeNumbers: [1])
    ])
    #expect(episode.reportedSeriesIDs == [
        ProviderReference(provider: "tvmaze", value: "123"),
        ProviderReference(provider: "thetvdb", value: "456"),
        ProviderReference(provider: "imdb", value: "tt789"),
    ])

    let season = page.candidates[1]
    #expect(season.id.value == "release-season-1")
    #expect(season.coverage == [
        CandidateCoverage(scope: .televisionSeason, seasonNumber: 1)
    ])
    #expect(season.reportedTraits == ReportedReleaseTraits(
        videoCodec: "HEVC",
        resolution: "1080p",
        source: "WEB-DL"
    ))

    let observedShape = page.candidates[2]
    #expect(observedShape.id.value == "release-observed-shape-1")
    #expect(observedShape.sizeBytes == 436_327_000)
    #expect(observedShape.coverage == [
        CandidateCoverage(scope: .televisionEpisode, seasonNumber: 1, episodeNumbers: [12])
    ])
    #expect(observedShape.reportedTraits.source == "HDTV")

    let encoded = String(decoding: try JSONEncoder().encode(page.candidates), as: UTF8.self)
    #expect(!encoded.contains("indexer.example"))
    #expect(!encoded.contains("t=get"))
}

@Test(arguments: [
    ("Show.S02E03.720p.HDTV.x264", 2, [3]),
    ("Show.S02E03E04.1080p.WEB-DL.x265", 2, [3, 4]),
    ("Show.S02E03-E05.2160p.WEB-DL.HEVC", 2, [3, 4, 5]),
    ("Show.2x03-2x05.1080p.BluRay.AV1", 2, [3, 4, 5]),
])
func parsesEpisodeTitleShapes(title: String, season: Int, episodes: [Int]) {
    let parsed = ReleaseTitleParser.parse(title)

    #expect(parsed.coverage == [
        CandidateCoverage(
            scope: .televisionEpisode,
            seasonNumber: season,
            episodeNumbers: episodes
        )
    ])
}

@Test func parsesNormalizedReleaseTraits() {
    let parsed = ReleaseTitleParser.parse("Show.S01E01.4K.WEBRip.H.265-GROUP")

    #expect(parsed.traits == ReportedReleaseTraits(
        videoCodec: "HEVC",
        resolution: "2160p",
        source: "WEBRip"
    ))
}

@Test func rejectsDescendingAndCrossSeasonRanges() {
    #expect(ReleaseTitleParser.parse("Show.S01E05-E03.1080p").coverage.isEmpty)
    #expect(ReleaseTitleParser.parse("Show.S01E03-S02E05.1080p").coverage.isEmpty)
    #expect(ReleaseTitleParser.parse("Show.1x03-2x05.1080p").coverage.isEmpty)
}

@Test func decodesProviderError() throws {
    let data = Data(#"<error code="100" description="Incorrect user credentials"/>"#.utf8)

    #expect(throws: NewznabResponseError.providerError(
        code: "100",
        description: "Incorrect user credentials"
    )) {
        try NewznabResponseDecoder.decode(data, provider: "nzbgeek")
    }
}

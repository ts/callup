import Foundation
import Testing
@testable import CallupCore

@Test func televisionDownloadsDefaultToShowAndSeasonFolders() {
    let show = TelevisionSeries(
        id: ProviderReference(provider: "tvmaze", value: "42"),
        title: "Some: Show",
        premieredYear: nil,
        status: nil,
        network: nil,
        imageURL: nil
    )

    let nested = TelevisionDownloadDestination(
        series: show,
        seasonNumber: 3,
        settings: TelevisionDownloadSettings()
    )
    let flat = TelevisionDownloadDestination(
        series: show,
        seasonNumber: 3,
        settings: TelevisionDownloadSettings(seasonFolders: false)
    )

    #expect(nested.categoryName == "callup-tvmaze-42-s03")
    #expect(nested.relativeDirectory == "Some- Show/Season 3/*")
    #expect(flat.categoryName == "callup-tvmaze-42")
    #expect(flat.relativeDirectory == "Some- Show/*")
}

@Test func releasePreferencesPutExactMatchesFirstWithoutHidingAlternatives() {
    let candidates = [
        release(id: "unknown"),
        release(id: "avc-1080", resolution: "1080p", codec: "AVC"),
        release(id: "hevc-1080", resolution: "1080p", codec: "HEVC"),
        release(id: "hevc-720", resolution: "720p", codec: "HEVC"),
    ]

    let ranked = ReleasePreferenceRanker.sorted(
        candidates,
        settings: TelevisionDownloadSettings(
            preferredResolution: .p1080,
            preferredVideoCodec: .hevc
        )
    )

    #expect(ranked.map(\.id.value) == ["hevc-1080", "avc-1080", "hevc-720", "unknown"])
}

@Test func rejectsAConflictingSeriesIdentityForAnAmbiguousTitle() {
    let original = TelevisionSeries(
        id: ProviderReference(provider: "tvmaze", value: "567"),
        title: "Gossip Girl",
        premieredYear: 2007,
        status: "Ended",
        network: "The CW",
        imageURL: nil,
        theTVDBID: "80547",
        imdbID: "tt0397442"
    )
    let rebootRelease = ReleaseCandidate(
        id: ProviderReference(provider: "indexer", value: "reboot-s01e06"),
        title: "Gossip.Girl.S01E06.Parentsite.1080p.WEBRip",
        sizeBytes: nil,
        publishedAt: nil,
        reportedMediaIDs: [
            ProviderReference(provider: "thetvdb", value: "377114"),
            ProviderReference(provider: "imdb", value: "tt10653784"),
        ]
    )

    #expect(!ReleaseIdentityFilter.matches(
        rebootRelease,
        series: original,
        requireReportedIdentity: true
    ))
}

@Test func acceptsAnUnidentifiedResultFromAnIdentifierScopedSearch() {
    let original = TelevisionSeries(
        id: ProviderReference(provider: "tvmaze", value: "567"),
        title: "Gossip Girl",
        premieredYear: 2007,
        status: "Ended",
        network: "The CW",
        imageURL: nil,
        theTVDBID: "80547",
        imdbID: "tt0397442"
    )
    let unidentified = ReleaseCandidate(
        id: ProviderReference(provider: "indexer", value: "unknown-s01e06"),
        title: "Gossip.Girl.S01E06.1080p.WEBRip",
        sizeBytes: nil,
        publishedAt: nil
    )

    #expect(ReleaseIdentityFilter.matches(
        unidentified,
        series: original,
        requireReportedIdentity: false
    ))
}

@Test func groupsAndOrdersEpisodesBySeason() {
    let seriesID = ProviderReference(provider: "fixture", value: "show")
    let episodes = [
        episode(id: "3", seriesID: seriesID, season: 2, number: 1),
        episode(id: "2", seriesID: seriesID, season: 1, number: 2),
        episode(id: "1", seriesID: seriesID, season: 1, number: 1),
    ]

    let seasons = TelevisionCatalog.seasons(from: episodes)

    #expect(seasons.map(\.number) == [1, 2])
    #expect(seasons[0].episodes.compactMap(\.episodeNumber) == [1, 2])
}

@Test func findsTheNextAnnouncedAirDate() {
    let seriesID = ProviderReference(provider: "fixture", value: "show")
    let episodes = [
        episode(id: "past", seriesID: seriesID, season: 1, number: 1, airDate: "2026-08-01"),
        episode(id: "later", seriesID: seriesID, season: 1, number: 3, airDate: "2026-08-20"),
        episode(id: "next", seriesID: seriesID, season: 1, number: 2, airDate: "2026-08-13"),
        episode(id: "tba", seriesID: seriesID, season: 1, number: 4),
    ]

    #expect(
        TelevisionCatalog.nextAirDate(from: episodes, onOrAfter: "2026-08-06")
            == "2026-08-13"
    )
}

@Test func futureMonitoringUsesACutoffAndEpisodeOverrides() {
    let seriesID = ProviderReference(provider: "fixture", value: "show")
    let past = episode(
        id: "past",
        seriesID: seriesID,
        season: 1,
        number: 1,
        airDate: "2026-08-09"
    )
    let today = episode(
        id: "today",
        seriesID: seriesID,
        season: 1,
        number: 2,
        airDate: "2026-08-10"
    )
    let future = episode(
        id: "future",
        seriesID: seriesID,
        season: 1,
        number: 3,
        airDate: "2026-08-17"
    )
    let undated = episode(id: "undated", seriesID: seriesID, season: 1, number: 4)
    let lineup = TelevisionLineup(
        monitoring: .future,
        futureCutoffDate: "2026-08-10",
        excludedEpisodes: [future.id],
        includedEpisodes: [past.id]
    )

    #expect(lineup.includes(past))
    #expect(lineup.includes(today))
    #expect(!lineup.includes(future))
    #expect(!lineup.includes(undated))
}

@Test func legacyLineupPayloadRetainsItsAllEpisodesMeaning() throws {
    let data = Data(#"{"excludedSeasons":[2],"excludedEpisodes":[]}"#.utf8)
    let lineup = try JSONDecoder().decode(TelevisionLineup.self, from: data)

    #expect(lineup.monitoring == .all)
    #expect(lineup.futureCutoffDate == nil)
    #expect(lineup.includedEpisodes.isEmpty)
    #expect(lineup.excludedSeasons == [2])
}

private func episode(
    id: String,
    seriesID: ProviderReference,
    season: Int,
    number: Int?,
    airDate: String? = nil
) -> TelevisionEpisode {
    TelevisionEpisode(
        id: ProviderReference(provider: "fixture", value: id),
        seriesID: seriesID,
        seasonNumber: season,
        episodeNumber: number,
        title: "Episode \(id)",
        airDate: airDate,
        runtimeMinutes: nil
    )
}

private func release(
    id: String,
    resolution: String? = nil,
    codec: String? = nil
) -> ReleaseCandidate {
    ReleaseCandidate(
        id: ProviderReference(provider: "fixture", value: id),
        title: id,
        sizeBytes: nil,
        publishedAt: nil,
        reportedTraits: ReportedReleaseTraits(videoCodec: codec, resolution: resolution)
    )
}

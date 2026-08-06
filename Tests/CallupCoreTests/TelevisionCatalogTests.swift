import Testing
@testable import CallupCore

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

private func episode(
    id: String,
    seriesID: ProviderReference,
    season: Int,
    number: Int?
) -> TelevisionEpisode {
    TelevisionEpisode(
        id: ProviderReference(provider: "fixture", value: id),
        seriesID: seriesID,
        seasonNumber: season,
        episodeNumber: number,
        title: "Episode \(id)",
        airDate: nil,
        runtimeMinutes: nil
    )
}

import CallupCore
import Foundation
import Testing
@testable import CallupTVMaze

@Test func decodesSeriesSearchWithoutLeakingProviderShape() throws {
    let data = Data(#"""
    [
      {
        "score": 0.99,
        "show": {
          "id": 123,
          "name": "A Great Show",
          "premiered": "2024-03-01",
          "status": "Running",
          "network": null,
          "webChannel": { "name": "Example+" },
          "image": { "medium": "https://example.test/poster.jpg" }
        }
      }
    ]
    """#.utf8)

    let results = try TVMazeDecoder.decodeSearch(data)

    #expect(results == [
        TelevisionSeries(
            id: ProviderReference(provider: "tvmaze", value: "123"),
            title: "A Great Show",
            premieredYear: 2024,
            status: "Running",
            network: "Example+",
            imageURL: "https://example.test/poster.jpg"
        )
    ])
}

@Test func decodesEpisodesAndPreservesSeriesIdentity() throws {
    let data = Data(#"""
    [
      {
        "id": 9001,
        "name": "The Beginning",
        "season": 1,
        "number": 1,
        "airdate": "2024-03-01",
        "runtime": 48
      }
    ]
    """#.utf8)
    let seriesID = ProviderReference(provider: "tvmaze", value: "123")

    let episodes = try TVMazeDecoder.decodeEpisodes(data, seriesID: seriesID)

    #expect(episodes.count == 1)
    #expect(episodes[0].seriesID == seriesID)
    #expect(episodes[0].seasonNumber == 1)
    #expect(episodes[0].episodeNumber == 1)
    #expect(episodes[0].runtimeMinutes == 48)
}

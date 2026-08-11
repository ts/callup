import CallupCore
import Testing

@Test func televisionAndMoviesUseTheSameAcquisitionShape() {
    let seriesID = ProviderReference(provider: "tvmaze", value: "1")
    let episodeID = ProviderReference(provider: "tvmaze", value: "2")
    let television = AcquisitionContext.television(
        seriesID: seriesID,
        episodeIDs: [episodeID]
    )

    #expect(television.targets == [
        AcquisitionTarget(
            media: MediaReference(kind: .televisionEpisode, id: episodeID),
            ancestors: [MediaReference(kind: .televisionSeries, id: seriesID)]
        )
    ])

    let collectionID = ProviderReference(provider: "fixture", value: "collection")
    let movieID = ProviderReference(provider: "fixture", value: "movie")
    let movie = AcquisitionContext.movie(movieID, collectionIDs: [collectionID])

    #expect(movie.targets == [
        AcquisitionTarget(
            media: MediaReference(kind: .movie, id: movieID),
            ancestors: [MediaReference(kind: .movieCollection, id: collectionID)]
        )
    ])
}

@Test func televisionAndMoviePreferencesRankTheSameCandidateTraits() {
    let matching = ReleaseCandidate(
        id: ProviderReference(provider: "fixture", value: "matching"),
        title: "Matching",
        sizeBytes: nil,
        publishedAt: nil,
        reportedTraits: ReportedReleaseTraits(videoCodec: "AV1", resolution: "2160p")
    )
    let other = ReleaseCandidate(
        id: ProviderReference(provider: "fixture", value: "other"),
        title: "Other",
        sizeBytes: nil,
        publishedAt: nil
    )
    let settings = MovieDownloadSettings(
        preferredResolution: .p2160,
        preferredVideoCodec: .av1
    )

    #expect(ReleasePreferenceRanker.sorted([other, matching], settings: settings) == [
        matching, other,
    ])
}

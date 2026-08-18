import CallupCore
import Foundation
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

@Test func universalSearchInterleavesTypedResults() throws {
    let series = TelevisionSeries(
        id: ProviderReference(provider: "television", value: "1"),
        title: "A Show",
        premieredYear: 2024,
        status: nil,
        network: nil,
        imageURL: nil
    )
    let movie = Movie(
        id: ProviderReference(provider: "movies", value: "2"),
        title: "A Movie",
        releaseYear: 2025,
        imageURL: nil
    )
    let results = MediaSearchResult.interleaving(
        televisionSeries: [series],
        movies: [movie]
    )

    #expect(results == [.televisionSeries(series), .movie(movie)])

    let encoded = try JSONEncoder().encode(results)
    #expect(try JSONDecoder().decode([MediaSearchResult].self, from: encoded) == results)
    let json = String(decoding: encoded, as: UTF8.self)
    #expect(json.contains(#""kind":"televisionSeries""#))
    #expect(json.contains(#""kind":"movie""#))
}

@Test func movieIdentityRejectsAReportedIMDbMismatch() {
    let movie = Movie(
        id: ProviderReference(provider: "tmdb", value: "284"),
        title: "The Apartment",
        releaseYear: 1960,
        imageURL: nil,
        imdbID: "tt0053604"
    )
    let matching = ReleaseCandidate(
        id: ProviderReference(provider: "indexer", value: "matching"),
        title: "The.Apartment.1960.1080p.BluRay",
        sizeBytes: nil,
        publishedAt: nil,
        reportedMediaIDs: [ProviderReference(provider: "imdb", value: "00053604")]
    )
    let conflicting = ReleaseCandidate(
        id: ProviderReference(provider: "indexer", value: "conflicting"),
        title: "The.Apartment.1996.1080p.WEB-DL",
        sizeBytes: nil,
        publishedAt: nil,
        reportedMediaIDs: [ProviderReference(provider: "imdb", value: "0115561")]
    )

    #expect(ReleaseIdentityFilter.matches(matching, movie: movie, requireReportedIdentity: true))
    #expect(!ReleaseIdentityFilter.matches(conflicting, movie: movie, requireReportedIdentity: true))
}

@Test func libraryInventoryRecognizesMovieFoldersAndUnrenamedTelevisionFiles() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "callup-library-\(UUID().uuidString)", directoryHint: .isDirectory)
    let movies = root.appending(path: "Movies", directoryHint: .isDirectory)
    let television = root.appending(path: "TV", directoryHint: .isDirectory)
    let drive = movies.appending(path: "Drive (2011)", directoryHint: .isDirectory)
    let show = television.appending(path: "A Great Show", directoryHint: .isDirectory)
        .appending(path: "Season 01", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: show, withIntermediateDirectories: true)
    let movieFile = drive.appending(path: "Drive.2011.1080p.HEVC.BluRay.mkv")
    let episodeFile = show.appending(path: "whatever-S01E02.720p.x264.WEB-DL.mkv")
    FileManager.default.createFile(
        atPath: movieFile.path,
        contents: Data(repeating: 1, count: 3_145_728)
    )
    FileManager.default.createFile(
        atPath: episodeFile.path,
        contents: Data(repeating: 1, count: 1_024)
    )

    let inventory = LibraryInventory()
    let snapshot = await inventory.snapshot(for: LibrarySettings(
        televisionRoot: television.path,
        movieRoot: movies.path
    ))
    let movie = Movie(
        id: ProviderReference(provider: "fixture", value: "drive"),
        title: "Drive",
        releaseYear: 2011,
        imageURL: nil
    )
    let series = TelevisionSeries(
        id: ProviderReference(provider: "fixture", value: "show"),
        title: "A Great Show",
        premieredYear: nil,
        status: nil,
        network: nil,
        imageURL: nil
    )
    let found = TelevisionEpisode(
        id: ProviderReference(provider: "fixture", value: "episode-2"),
        seriesID: series.id,
        seasonNumber: 1,
        episodeNumber: 2,
        title: "Two",
        airDate: nil,
        runtimeMinutes: nil
    )
    let missing = TelevisionEpisode(
        id: ProviderReference(provider: "fixture", value: "episode-3"),
        seriesID: series.id,
        seasonNumber: 1,
        episodeNumber: 3,
        title: "Three",
        airDate: nil,
        runtimeMinutes: nil
    )

    #expect(snapshot.contains(movie))
    #expect(snapshot.episodeIDsOnDisk(for: series, episodes: [found, missing]) == Set([found.id]))
    let movieDetails = try #require(snapshot.filesOnDisk(for: movie).first)
    #expect(movieDetails.name == "Drive.2011.1080p.HEVC.BluRay.mkv")
    #expect(movieDetails.relativePath == "Drive (2011)/Drive.2011.1080p.HEVC.BluRay.mkv")
    #expect(movieDetails.sizeBytes == 3_145_728)
    #expect(movieDetails.inferredTraits == ReportedReleaseTraits(
        videoCodec: "HEVC",
        resolution: "1080p",
        source: "BluRay"
    ))
    let episodeDetails = try #require(
        snapshot.episodeFilesOnDisk(for: series, episodes: [found, missing])[found.id]?.first
    )
    #expect(episodeDetails.name == "whatever-S01E02.720p.x264.WEB-DL.mkv")
    #expect(episodeDetails.sizeBytes == 1_024)
    #expect(episodeDetails.inferredTraits == ReportedReleaseTraits(
        videoCodec: "AVC",
        resolution: "720p",
        source: "WEB-DL"
    ))
}

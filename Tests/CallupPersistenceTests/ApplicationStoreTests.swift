import CallupCore
import Foundation
import Testing
@testable import CallupPersistence

@Test func connectionSettingsStayOutsideSQLiteWithOwnerOnlyPermissions() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let fileURL = directory.appending(path: "connections.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ConnectionSettingsStore(fileURL: fileURL)
    let connection = IndexerConnection(
        name: "NZBGeek",
        endpoint: try #require(URL(string: "https://example.invalid/api")),
        apiKey: "fixture-secret"
    )

    try await store.setIndexer(connection)
    try await store.setMetadataProvider(MetadataProviderConnection(
        provider: "tmdb",
        secret: "tmdb-fixture-secret"
    ))
    let reopened = try ConnectionSettingsStore(fileURL: fileURL)
    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)

    #expect(await reopened.load().indexer == connection)
    #expect(await reopened.load().metadataProviders == [MetadataProviderConnection(
        provider: "tmdb",
        secret: "tmdb-fixture-secret"
    )])
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test func legacyConnectionSettingsDecodeWithoutMetadataProviders() throws {
    let legacy = Data(#"{"indexer":null,"downloadClient":null}"#.utf8)

    let decoded = try JSONDecoder().decode(ConnectionSettings.self, from: legacy)

    #expect(decoded == ConnectionSettings())
}

@Test func connectionSettingsCanBeReplacedByARestore() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let fileURL = directory.appending(path: "connections.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try ConnectionSettingsStore(fileURL: fileURL)
    let restored = ConnectionSettings(
        indexer: IndexerConnection(
            name: "Restored indexer",
            endpoint: try #require(URL(string: "https://example.invalid/api")),
            apiKey: "restored-secret"
        ),
        downloadClient: DownloadClientConnection(
            kind: .sabnzbd,
            endpoint: try #require(URL(string: "http://example.invalid:8080")),
            secret: "restored-download-secret"
        ),
        metadataProviders: [MetadataProviderConnection(
            provider: "tmdb",
            secret: "restored-tmdb-secret"
        )]
    )

    try await store.replace(with: restored)

    let reopened = try ConnectionSettingsStore(fileURL: fileURL)
    #expect(await reopened.load() == restored)
}

@Test func backupRoundTripRestoresDurableStateAndDiscardsCaches() async throws {
    let source = try await ApplicationStore.inMemory()
    let trackedSeries = series(id: "backup-show", title: "Backup Show")
    let trackedMovie = fixtureMovie(id: "backup-movie", title: "Backup Movie")
    let candidateID = ProviderReference(provider: "nzbgeek", value: "backup-release")
    let episodeID = ProviderReference(provider: "fixture", value: "backup-episode")

    try await source.trackTelevisionSeries(
        trackedSeries,
        addedAt: Date(timeIntervalSince1970: 1_000)
    )
    try await source.setTelevisionDownloadSettings(
        seriesID: trackedSeries.id,
        settings: TelevisionDownloadSettings(
            seasonFolders: false,
            preferredResolution: .p2160,
            preferredVideoCodec: .av1
        )
    )
    try await source.setTelevisionEpisodeIncluded(
        seriesID: trackedSeries.id,
        seasonNumber: 1,
        episodeID: episodeID,
        seasonEpisodeIDs: [episodeID],
        included: false
    )
    try await source.trackMovie(
        trackedMovie,
        addedAt: Date(timeIntervalSince1970: 2_000)
    )
    try await source.setMovieDownloadSettings(
        movieID: trackedMovie.id,
        settings: MovieDownloadSettings(
            preferredResolution: .p720,
            preferredVideoCodec: .avc
        )
    )
    _ = try await source.reserveDownloadSubmission(
        candidateID: candidateID,
        title: "Backup Show S01E01",
        client: .sabnzbd,
        at: Date(timeIntervalSince1970: 3_000)
    )
    _ = try await source.finishDownloadSubmission(
        candidateID: candidateID,
        jobID: "restored-job",
        at: Date(timeIntervalSince1970: 4_000)
    )
    _ = try await source.associateDownloadSubmission(
        candidateID: candidateID,
        seriesID: trackedSeries.id,
        episodeIDs: [episodeID],
        at: Date(timeIntervalSince1970: 5_000)
    )
    _ = try await source.updateDownloadSubmissionState(
        candidateID: candidateID,
        state: .downloaded,
        at: Date(timeIntervalSince1970: 6_000)
    )
    try await source.putCacheEntry(
        namespace: "fixture",
        key: "excluded-from-backup",
        value: ["disposable"],
        expiresAt: Date().addingTimeInterval(60)
    )

    let connections = ConnectionSettings(indexer: IndexerConnection(
        name: "Backup indexer",
        endpoint: try #require(URL(string: "https://example.invalid/api")),
        apiKey: "fixture-secret"
    ))
    let backup = try await source.exportBackup(
        exportedAt: Date(timeIntervalSince1970: 7_000),
        connections: connections
    )
    let encoded = try JSONEncoder().encode(backup)
    let decoded = try JSONDecoder().decode(CallupBackup.self, from: encoded)
    #expect(decoded == backup)

    let destination = try await ApplicationStore.inMemory()
    try await destination.trackMovie(fixtureMovie(id: "old", title: "Old Movie"))
    try await destination.putCacheEntry(
        namespace: "fixture",
        key: "old-cache",
        value: ["old"],
        expiresAt: Date().addingTimeInterval(60)
    )
    let summary = try await destination.restoreBackup(decoded)

    #expect(summary == BackupRestoreSummary(
        televisionCount: 1,
        movieCount: 1,
        downloadCount: 1,
        restoredConnections: true
    ))
    #expect(try await destination.trackedTelevisionSeries() == backup.television.map(\.tracked))
    #expect(try await destination.televisionLineup(seriesID: trackedSeries.id) == backup.television[0].lineup)
    #expect(try await destination.trackedMovies() == backup.movies)
    #expect(try await destination.downloadSubmissions() == backup.downloads)
    let cache: ApplicationStore.CacheEntry<[String]>? = try await destination.cacheEntry(
        namespace: "fixture",
        key: "old-cache"
    )
    #expect(cache == nil)

    try await source.close()
    try await destination.close()
}

@Test func invalidBackupDoesNotReplaceExistingState() async throws {
    let store = try await ApplicationStore.inMemory()
    let existing = fixtureMovie(id: "existing", title: "Existing Movie")
    let duplicate = TrackedMovie(movie: fixtureMovie(id: "duplicate", title: "Duplicate"), addedAt: Date())
    try await store.trackMovie(existing)
    let backup = CallupBackup(
        television: [],
        movies: [duplicate, duplicate],
        downloads: []
    )

    await #expect(throws: ApplicationStore.StoreError.invalidBackup) {
        try await store.restoreBackup(backup)
    }
    #expect(try await store.trackedMovies().map(\.movie) == [existing])
    try await store.close()
}

@Test func storesOneReplaceableCacheEntry() async throws {
    let store = try await ApplicationStore.inMemory()
    let fetchedAt = Date(timeIntervalSince1970: 1_000)
    let expiresAt = Date(timeIntervalSince1970: 2_000)

    try await store.putCacheEntry(
        namespace: "fixture",
        key: "one",
        value: ["first"],
        fetchedAt: fetchedAt,
        expiresAt: expiresAt
    )
    try await store.putCacheEntry(
        namespace: "fixture",
        key: "one",
        value: ["replacement"],
        fetchedAt: fetchedAt,
        expiresAt: expiresAt
    )

    let entry: ApplicationStore.CacheEntry<[String]>? = try await store.cacheEntry(
        namespace: "fixture",
        key: "one"
    )
    #expect(entry?.value == ["replacement"])
    #expect(entry?.fetchedAt == fetchedAt)
    #expect(entry?.expiresAt == expiresAt)
    #expect(entry?.isFresh(at: Date(timeIntervalSince1970: 1_500)) == true)
    #expect(entry?.isFresh(at: expiresAt) == false)

    try await store.close()
}

@Test func fileStoreSurvivesReopen() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "callup-store-\(UUID().uuidString)", directoryHint: .isDirectory)
    let fileURL = directory.appending(path: "callup.sqlite")
    defer { try? FileManager.default.removeItem(at: directory) }

    let first = try await ApplicationStore.open(fileURL: fileURL)
    try await first.putCacheEntry(
        namespace: "fixture",
        key: "persistent",
        value: ["survived"],
        expiresAt: Date().addingTimeInterval(60)
    )
    try await first.close()

    let second = try await ApplicationStore.open(fileURL: fileURL)
    let entry: ApplicationStore.CacheEntry<[String]>? = try await second.cacheEntry(
        namespace: "fixture",
        key: "persistent"
    )

    #expect(entry?.value == ["survived"])
    try await second.close()
}

@Test func rejectsEmptyCacheIdentity() async throws {
    let store = try await ApplicationStore.inMemory()

    await #expect(throws: ApplicationStore.StoreError.invalidCacheIdentity) {
        try await store.putCacheEntry(
            namespace: " ",
            key: "one",
            value: ["value"],
            expiresAt: Date().addingTimeInterval(60)
        )
    }

    try await store.close()
}

@Test func tracksUpdatesAndRemovesTelevisionSeries() async throws {
    let store = try await ApplicationStore.inMemory()
    let firstAddedAt = Date(timeIntervalSince1970: 1_000)
    let original = series(id: "one", title: "Zulu")
    let alphabeticallyFirst = series(id: "two", title: "Alpha")

    try await store.trackTelevisionSeries(original, addedAt: firstAddedAt)
    try await store.trackTelevisionSeries(alphabeticallyFirst)
    let updated = series(id: "one", title: "Bravo")
    let tracked = try await store.trackTelevisionSeries(
        updated,
        addedAt: Date(timeIntervalSince1970: 2_000)
    )

    #expect(tracked.series == updated)
    #expect(tracked.addedAt == firstAddedAt)
    #expect(try await store.trackedTelevisionSeries().map(\.series.title) == ["Alpha", "Bravo"])

    try await store.untrackTelevisionSeries(id: original.id)
    #expect(try await store.trackedTelevisionSeries().map(\.series.title) == ["Alpha"])

    try await store.close()
}

@Test func televisionAndMoviesShareAtomicTrackedMediaStorage() async throws {
    let store = try await ApplicationStore.inMemory()
    let show = series(id: "shared-id", title: "A Show")
    let movie = Movie(
        id: ProviderReference(provider: "fixture", value: "shared-id"),
        title: "A Movie",
        releaseYear: 2026,
        imageURL: nil,
        imdbID: "tt123"
    )

    _ = try await store.trackTelevisionSeries(show)
    _ = try await store.trackMovie(movie)
    _ = try await store.setMovieDownloadSettings(
        movieID: movie.id,
        settings: MovieDownloadSettings(
            preferredResolution: .p2160,
            preferredVideoCodec: .av1
        )
    )

    #expect(try await store.trackedTelevisionSeries().map(\.series) == [show])
    #expect(try await store.trackedMovies().map(\.movie) == [movie])
    #expect(try await store.trackedMovie(id: movie.id)?.downloadSettings == MovieDownloadSettings(
        preferredResolution: .p2160,
        preferredVideoCodec: .av1
    ))

    try await store.untrackMovie(id: movie.id)
    #expect(try await store.trackedMovies().isEmpty)
    #expect(try await store.trackedTelevisionSeries().map(\.series) == [show])
    try await store.close()
}

@Test func trackedMovieSurvivesReopen() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "callup-movie-\(UUID().uuidString)", directoryHint: .isDirectory)
    let fileURL = directory.appending(path: "callup.sqlite")
    defer { try? FileManager.default.removeItem(at: directory) }
    let movie = Movie(
        id: ProviderReference(provider: "fixture", value: "durable-movie"),
        title: "Durable Movie",
        releaseYear: 2026,
        imageURL: nil
    )

    let first = try await ApplicationStore.open(fileURL: fileURL)
    _ = try await first.trackMovie(movie, addedAt: Date(timeIntervalSince1970: 1_000))
    try await first.close()

    let second = try await ApplicationStore.open(fileURL: fileURL)
    let tracked = try await second.trackedMovie(id: movie.id)
    #expect(tracked?.movie == movie)
    #expect(tracked?.addedAt == Date(timeIntervalSince1970: 1_000))
    try await second.close()
}

@Test func trackedMovieMetadataCanHydrateWithoutResettingPreferencesOrReadding() async throws {
    let store = try await ApplicationStore.inMemory()
    let summary = Movie(
        id: ProviderReference(provider: "tmdb", value: "284"),
        title: "The Apartment",
        releaseYear: 1960,
        imageURL: nil
    )
    let detailed = Movie(
        id: summary.id,
        title: summary.title,
        releaseYear: summary.releaseYear,
        releaseDate: "1960-06-21",
        imageURL: nil,
        imdbID: "tt0053604"
    )
    let settings = MovieDownloadSettings(
        preferredResolution: .p2160,
        preferredVideoCodec: .av1
    )

    _ = try await store.trackMovie(summary)
    _ = try await store.setMovieDownloadSettings(movieID: summary.id, settings: settings)
    let hydrated = try await store.updateTrackedMovieMetadata(detailed)

    #expect(hydrated?.movie == detailed)
    #expect(hydrated?.downloadSettings == settings)

    try await store.untrackMovie(id: summary.id)
    #expect(try await store.updateTrackedMovieMetadata(detailed) == nil)
    #expect(try await store.trackedMovies().isEmpty)
    try await store.close()
}

@Test func trackedTelevisionSeriesSurviveReopen() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "callup-tracked-\(UUID().uuidString)", directoryHint: .isDirectory)
    let fileURL = directory.appending(path: "callup.sqlite")
    defer { try? FileManager.default.removeItem(at: directory) }

    let first = try await ApplicationStore.open(fileURL: fileURL)
    let persistentSeries = series(id: "persistent", title: "Persistent Show")
    try await first.trackTelevisionSeries(persistentSeries)
    try await first.setTelevisionDownloadSettings(
        seriesID: persistentSeries.id,
        settings: TelevisionDownloadSettings(
            seasonFolders: false,
            preferredResolution: .p2160,
            preferredVideoCodec: .av1
        )
    )
    try await first.setTelevisionSeasonIncluded(
        seriesID: persistentSeries.id,
        seasonNumber: 2,
        episodeIDs: [],
        included: false
    )
    try await first.close()

    let second = try await ApplicationStore.open(fileURL: fileURL)
    #expect(try await second.trackedTelevisionSeries().map(\.series.title) == ["Persistent Show"])
    #expect(try await second.televisionLineup(seriesID: persistentSeries.id).excludedSeasons == [2])
    #expect(try await second.trackedTelevisionSeries(id: persistentSeries.id)?.downloadSettings.seasonFolders == false)
    #expect(try await second.trackedTelevisionSeries(id: persistentSeries.id)?.downloadSettings.preferredResolution == .p2160)
    #expect(try await second.trackedTelevisionSeries(id: persistentSeries.id)?.downloadSettings.preferredVideoCodec == .av1)
    try await second.close()
}

@Test func televisionDownloadSettingsDefaultOnAndRequireATrackedSeries() async throws {
    let store = try await ApplicationStore.inMemory()
    let tracked = series(id: "folders", title: "Folder Show")
    try await store.trackTelevisionSeries(tracked)

    #expect(try await store.trackedTelevisionSeries(id: tracked.id)?.downloadSettings.seasonFolders == true)
    #expect(try await store.trackedTelevisionSeries(id: tracked.id)?.downloadSettings.preferredResolution == .p1080)
    #expect(try await store.trackedTelevisionSeries(id: tracked.id)?.downloadSettings.preferredVideoCodec == .hevc)
    let updated = try await store.setTelevisionDownloadSettings(
        seriesID: tracked.id,
        settings: TelevisionDownloadSettings(
            seasonFolders: false,
            preferredResolution: .p720,
            preferredVideoCodec: .av1
        )
    )
    #expect(updated.seasonFolders == false)
    #expect(try await store.trackedTelevisionSeries(id: tracked.id)?.downloadSettings == updated)

    await #expect(throws: ApplicationStore.StoreError.seriesNotTracked) {
        try await store.setTelevisionDownloadSettings(
            seriesID: ProviderReference(provider: "fixture", value: "missing"),
            settings: TelevisionDownloadSettings()
        )
    }
    try await store.close()
}

@Test func televisionLineupCascadesFromSeriesToSeasonsAndEpisodes() async throws {
    let store = try await ApplicationStore.inMemory()
    let tracked = series(id: "lineup", title: "Lineup Show")
    let episodeOne = ProviderReference(provider: "fixture", value: "episode-one")
    let episodeTwo = ProviderReference(provider: "fixture", value: "episode-two")
    try await store.trackTelevisionSeries(tracked)

    #expect(try await store.televisionLineup(seriesID: tracked.id) == TelevisionLineup())

    try await store.setTelevisionEpisodeIncluded(
        seriesID: tracked.id,
        seasonNumber: 1,
        episodeID: episodeOne,
        seasonEpisodeIDs: [episodeOne, episodeTwo],
        included: false
    )
    #expect(try await store.televisionLineup(seriesID: tracked.id).excludedEpisodes == [episodeOne])

    try await store.setTelevisionSeasonIncluded(
        seriesID: tracked.id,
        seasonNumber: 1,
        episodeIDs: [episodeOne, episodeTwo],
        included: false
    )
    #expect(try await store.televisionLineup(seriesID: tracked.id) == TelevisionLineup(
        excludedSeasons: [1],
        excludedEpisodes: []
    ))

    try await store.setTelevisionEpisodeIncluded(
        seriesID: tracked.id,
        seasonNumber: 1,
        episodeID: episodeOne,
        seasonEpisodeIDs: [episodeOne, episodeTwo],
        included: true
    )
    #expect(try await store.televisionLineup(seriesID: tracked.id) == TelevisionLineup(
        excludedSeasons: [],
        excludedEpisodes: [episodeTwo],
        includedEpisodes: [episodeOne]
    ))

    try await store.setTelevisionEpisodeIncluded(
        seriesID: tracked.id,
        seasonNumber: 1,
        episodeID: episodeOne,
        seasonEpisodeIDs: [episodeOne, episodeTwo],
        included: false
    )
    #expect(try await store.televisionLineup(seriesID: tracked.id) == TelevisionLineup(
        excludedSeasons: [],
        excludedEpisodes: [episodeOne, episodeTwo]
    ))

    try await store.setTelevisionSeasonIncluded(
        seriesID: tracked.id,
        seasonNumber: 1,
        episodeIDs: [episodeOne, episodeTwo],
        included: true
    )
    #expect(try await store.televisionLineup(seriesID: tracked.id) == TelevisionLineup(
        includedEpisodes: [episodeOne, episodeTwo]
    ))

    try await store.untrackTelevisionSeries(id: tracked.id)
    try await store.trackTelevisionSeries(tracked)
    #expect(try await store.televisionLineup(seriesID: tracked.id) == TelevisionLineup())
    try await store.close()
}

@Test func episodeMonitoringPolicyIsDurableAndClearsOldOverrides() async throws {
    let store = try await ApplicationStore.inMemory()
    let tracked = series(id: "monitoring", title: "Monitoring Show")
    let episodeID = ProviderReference(provider: "fixture", value: "episode")
    try await store.trackTelevisionSeries(tracked)
    try await store.setTelevisionEpisodeIncluded(
        seriesID: tracked.id,
        seasonNumber: 1,
        episodeID: episodeID,
        seasonEpisodeIDs: [episodeID],
        included: false
    )

    try await store.setTelevisionEpisodeMonitoring(
        seriesID: tracked.id,
        monitoring: .future,
        futureCutoffDate: "2026-08-10"
    )
    let lineup = try await store.televisionLineup(seriesID: tracked.id)

    #expect(lineup.monitoring == .future)
    #expect(lineup.futureCutoffDate == "2026-08-10")
    #expect(lineup.excludedSeasons.isEmpty)
    #expect(lineup.excludedEpisodes.isEmpty)
    #expect(lineup.includedEpisodes.isEmpty)
    try await store.close()
}

@Test func cannotSetLineupForUntrackedSeries() async throws {
    let store = try await ApplicationStore.inMemory()

    await #expect(throws: ApplicationStore.StoreError.seriesNotTracked) {
        try await store.setTelevisionSeasonIncluded(
            seriesID: ProviderReference(provider: "fixture", value: "missing"),
            seasonNumber: 1,
            episodeIDs: [],
            included: false
        )
    }
    try await store.close()
}

@Test func downloadSubmissionIsDurableAndIdempotent() async throws {
    let store = try await ApplicationStore.inMemory()
    let candidateID = ProviderReference(provider: "nzbgeek", value: "release-one")
    let createdAt = Date(timeIntervalSince1970: 1_000)

    let first = try await store.reserveDownloadSubmission(
        candidateID: candidateID,
        title: "A Great Show S01E01",
        client: .sabnzbd,
        at: createdAt
    )
    guard case let .reserved(reserved) = first else {
        Issue.record("The first submission was not reserved.")
        return
    }
    #expect(reserved.state == .sending)

    let duplicate = try await store.reserveDownloadSubmission(
        candidateID: candidateID,
        title: "A Great Show S01E01",
        client: .sabnzbd
    )
    guard case let .existing(existing) = duplicate else {
        Issue.record("A duplicate submission was reserved.")
        return
    }
    #expect(existing.state == .sending)

    let queued = try await store.finishDownloadSubmission(
        candidateID: candidateID,
        jobID: "SABnzbd_nzo_fixture",
        at: Date(timeIntervalSince1970: 2_000)
    )
    #expect(queued.state == .snatched)
    #expect(queued.clientJobID == "SABnzbd_nzo_fixture")
    #expect(queued.createdAt == createdAt)

    let afterQueue = try await store.reserveDownloadSubmission(
        candidateID: candidateID,
        title: "A Great Show S01E01",
        client: .sabnzbd
    )
    guard case let .existing(stillQueued) = afterQueue else {
        Issue.record("A queued submission was reserved again.")
        return
    }
    #expect(stillQueued.clientJobID == "SABnzbd_nzo_fixture")
    try await store.close()
}

@Test func failedDownloadSubmissionCanBeExplicitlyRetried() async throws {
    let store = try await ApplicationStore.inMemory()
    let candidateID = ProviderReference(provider: "nzbgeek", value: "release-retry")
    _ = try await store.reserveDownloadSubmission(
        candidateID: candidateID,
        title: "Retry Me",
        client: .sabnzbd
    )
    try await store.failDownloadSubmission(candidateID: candidateID)

    let retry = try await store.reserveDownloadSubmission(
        candidateID: candidateID,
        title: "Retry Me",
        client: .sabnzbd
    )
    guard case let .reserved(submission) = retry else {
        Issue.record("A failed submission could not be retried.")
        return
    }
    #expect(submission.state == .sending)
    try await store.close()
}

@Test func downloadSubmissionCanBeAssociatedWithTelevisionEpisodes() async throws {
    let store = try await ApplicationStore.inMemory()
    let candidateID = ProviderReference(provider: "nzbgeek", value: "release-context")
    let seriesID = ProviderReference(provider: "tvmaze", value: "123")
    let episodeIDs = [
        ProviderReference(provider: "tvmaze", value: "456"),
        ProviderReference(provider: "tvmaze", value: "457"),
    ]
    _ = try await store.reserveDownloadSubmission(
        candidateID: candidateID,
        title: "A Great Show S01E01-E02",
        client: .sabnzbd
    )

    let associated = try await store.associateDownloadSubmission(
        candidateID: candidateID,
        seriesID: seriesID,
        episodeIDs: episodeIDs
    )

    let context = AcquisitionContext.television(seriesID: seriesID, episodeIDs: episodeIDs)
    #expect(associated.acquisitionContext == context)
    #expect(try await store.downloadSubmission(candidateID: candidateID)?.acquisitionContext == context)
    try await store.close()
}

@Test func downloadSubmissionAssociatesWithAnyAtomicMediaTarget() async throws {
    let store = try await ApplicationStore.inMemory()
    let candidateID = ProviderReference(provider: "nzbgeek", value: "movie-release")
    let movieID = ProviderReference(provider: "fixture", value: "movie")
    _ = try await store.reserveDownloadSubmission(
        candidateID: candidateID,
        title: "A Movie 2026 1080p",
        client: .sabnzbd
    )

    let context = AcquisitionContext.movie(movieID)
    let associated = try await store.associateDownloadSubmission(
        candidateID: candidateID,
        acquisitionContext: context
    )

    #expect(associated.acquisitionContext == context)
    #expect(try await store.downloadSubmission(candidateID: candidateID)?.acquisitionContext == context)
    try await store.close()
}

@Test func downloadSubmissionPersistsTelevisionSeasonAsAnAncestor() async throws {
    let store = try await ApplicationStore.inMemory()
    let candidateID = ProviderReference(provider: "nzbgeek", value: "season-context")
    let seriesID = ProviderReference(provider: "tvmaze", value: "123")
    let episode = TelevisionEpisode(
        id: ProviderReference(provider: "tvmaze", value: "456"),
        seriesID: seriesID,
        seasonNumber: 2,
        episodeNumber: 1,
        title: "Episode",
        airDate: nil,
        runtimeMinutes: nil
    )
    _ = try await store.reserveDownloadSubmission(
        candidateID: candidateID,
        title: "A Great Show S02E01",
        client: .sabnzbd
    )

    let associated = try await store.associateDownloadSubmission(
        candidateID: candidateID,
        seriesID: seriesID,
        episodes: [episode]
    )

    #expect(associated.acquisitionContext?.televisionSeasonNumber == 2)
    #expect(associated.acquisitionContext?.targets.first?.ancestors == [
        .televisionSeason(seriesID: seriesID, number: 2),
        MediaReference(kind: .televisionSeries, id: seriesID),
    ])
    try await store.close()
}

@Test func queuedDownloadCannotBeSubmittedAgainAfterReopen() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "callup-download-\(UUID().uuidString)", directoryHint: .isDirectory)
    let fileURL = directory.appending(path: "callup.sqlite")
    defer { try? FileManager.default.removeItem(at: directory) }
    let candidateID = ProviderReference(provider: "nzbgeek", value: "release-durable")

    let first = try await ApplicationStore.open(fileURL: fileURL)
    _ = try await first.reserveDownloadSubmission(
        candidateID: candidateID,
        title: "Durable Download",
        client: .sabnzbd
    )
    _ = try await first.finishDownloadSubmission(
        candidateID: candidateID,
        jobID: "SABnzbd_nzo_durable"
    )
    try await first.close()

    let second = try await ApplicationStore.open(fileURL: fileURL)
    let duplicate = try await second.reserveDownloadSubmission(
        candidateID: candidateID,
        title: "Durable Download",
        client: .sabnzbd
    )
    guard case let .existing(submission) = duplicate else {
        Issue.record("A queued download was reserved again after reopening the store.")
        return
    }
    #expect(submission.state == .snatched)
    #expect(submission.clientJobID == "SABnzbd_nzo_durable")
    try await second.close()
}

@Test func incompatibleDisposableCacheReloadsInsteadOfFailing() async throws {
    let store = try await ApplicationStore.inMemory()
    try await store.putCacheEntry(
        namespace: "fixture",
        key: "changing-shape",
        value: ["old shape"],
        expiresAt: Date().addingTimeInterval(60)
    )

    let value: [Int] = try await store.cachedValue(
        namespace: "fixture",
        key: "changing-shape",
        timeToLive: 60
    ) {
        [42]
    }

    #expect(value == [42])
    try await store.close()
}

@Test func televisionMetadataUsesOneSharedCache() async throws {
    let store = try await ApplicationStore.inMemory()
    let upstream = MetadataStub(series: [series(title: "First")])
    let cached = CachedTelevisionMetadataProvider(upstream: upstream, store: store)

    let first = try await cached.searchSeries(query: " A Great Show ")
    await upstream.setSeries([series(title: "Changed upstream")])
    let second = try await cached.searchSeries(query: "a great show")

    #expect(first.map(\.title) == ["First"])
    #expect(second.map(\.title) == ["First"])
    #expect(await upstream.searchCount == 1)

    try await store.close()
}

@Test func staleTelevisionMetadataReturnsImmediatelyAndRefreshes() async throws {
    let store = try await ApplicationStore.inMemory()
    let upstream = MetadataStub(series: [series(title: "Cached")])
    let cached = CachedTelevisionMetadataProvider(
        upstream: upstream,
        store: store,
        seriesSearchTTL: -1
    )

    _ = try await cached.searchSeries(query: "A Great Show")
    await upstream.setSeries([series(title: "Fresh")])

    let stale = try await cached.searchSeries(query: "A Great Show")
    #expect(stale.map(\.title) == ["Cached"])

    var refreshed = stale
    for _ in 0..<100 where refreshed.map(\.title) != ["Fresh"] {
        try await Task.sleep(for: .milliseconds(10))
        refreshed = try await cached.searchSeries(query: "A Great Show")
    }

    #expect(await upstream.searchCount >= 2)
    #expect(refreshed.map(\.title) == ["Fresh"])

    try await store.close()
}

@Test func movieMetadataUsesItsSupplierCache() async throws {
    let store = try await ApplicationStore.inMemory()
    let upstream = MovieMetadataStub(movies: [fixtureMovie(title: "First")])
    let cached = CachedMovieMetadataProvider(upstream: upstream, store: store)

    let first = try await cached.searchMovies(query: " The Apartment ")
    await upstream.setMovies([fixtureMovie(title: "Changed upstream")])
    let second = try await cached.searchMovies(query: "the apartment")

    #expect(first.map(\.title) == ["First"])
    #expect(second.map(\.title) == ["First"])
    #expect(await upstream.searchCount == 1)

    try await store.close()
}

@Test func televisionReleaseSearchUsesTheSameStore() async throws {
    let store = try await ApplicationStore.inMemory()
    let upstream = ReleaseIndexerStub(page: releasePage(total: 2))
    let cached = CachedTelevisionReleaseIndexer(upstream: upstream, store: store)

    let first = try await cached.searchTelevision(
        query: "A Great Show",
        tvmazeID: "123",
        tvdbID: "456",
        imdbID: "tt789",
        season: 1,
        episode: nil
    )
    await upstream.setPage(releasePage(total: 99))
    let second = try await cached.searchTelevision(
        query: "a great show",
        tvmazeID: "123",
        tvdbID: "456",
        imdbID: "tt789",
        season: 1,
        episode: nil
    )

    #expect(first.total == 2)
    #expect(second.total == 2)
    #expect(await upstream.searchCount == 1)

    try await store.close()
}

@Test func movieReleaseSearchUsesTheSameStore() async throws {
    let store = try await ApplicationStore.inMemory()
    let upstream = MovieReleaseIndexerStub(page: releasePage(total: 2))
    let cached = CachedMovieReleaseIndexer(upstream: upstream, store: store)

    let first = try await cached.searchMovies(query: "The Apartment", imdbID: "tt0053604")
    await upstream.setPage(releasePage(total: 99))
    let second = try await cached.searchMovies(query: "the apartment", imdbID: "tt0053604")

    #expect(first.total == 2)
    #expect(second.total == 2)
    #expect(await upstream.searchCount == 1)

    try await store.close()
}

private actor MetadataStub: TelevisionMetadataSupplier {
    nonisolated let metadataSupplier = MetadataSupplier(
        id: "fixture",
        displayName: "Fixture",
        supportedMediaKinds: [.televisionSeries, .televisionEpisode]
    )
    private var series: [TelevisionSeries]
    private(set) var searchCount = 0

    init(series: [TelevisionSeries]) {
        self.series = series
    }

    func setSeries(_ series: [TelevisionSeries]) {
        self.series = series
    }

    func searchSeries(query: String) -> [TelevisionSeries] {
        searchCount += 1
        return series
    }

    func series(for seriesID: ProviderReference) -> TelevisionSeries {
        series.first { $0.id == seriesID } ?? series[0]
    }

    func episodes(for seriesID: ProviderReference) -> [TelevisionEpisode] {
        []
    }
}

private actor MovieMetadataStub: MovieMetadataSupplier {
    nonisolated let metadataSupplier = MetadataSupplier(
        id: "movie-fixture",
        displayName: "Movie Fixture",
        supportedMediaKinds: [.movie]
    )
    private var movies: [Movie]
    private(set) var searchCount = 0

    init(movies: [Movie]) {
        self.movies = movies
    }

    func setMovies(_ movies: [Movie]) {
        self.movies = movies
    }

    func searchMovies(query: String) -> [Movie] {
        searchCount += 1
        return movies
    }

    func movie(for movieID: ProviderReference) -> Movie {
        movies.first { $0.id == movieID } ?? movies[0]
    }
}

private actor ReleaseIndexerStub: TelevisionReleaseIndexer {
    private var page: ReleaseSearchPage
    private(set) var searchCount = 0

    init(page: ReleaseSearchPage) {
        self.page = page
    }

    func setPage(_ page: ReleaseSearchPage) {
        self.page = page
    }

    func searchTelevision(
        query: String,
        tvmazeID: String?,
        tvdbID: String?,
        imdbID: String?,
        season: Int?,
        episode: Int?
    ) -> ReleaseSearchPage {
        searchCount += 1
        return page
    }
}

private actor MovieReleaseIndexerStub: MovieReleaseIndexer {
    private var page: ReleaseSearchPage
    private(set) var searchCount = 0

    init(page: ReleaseSearchPage) {
        self.page = page
    }

    func setPage(_ page: ReleaseSearchPage) {
        self.page = page
    }

    func searchMovies(query: String, imdbID: String?) -> ReleaseSearchPage {
        searchCount += 1
        return page
    }
}

private func series(id: String = "one", title: String) -> TelevisionSeries {
    TelevisionSeries(
        id: ProviderReference(provider: "fixture", value: id),
        title: title,
        premieredYear: nil,
        status: nil,
        network: nil,
        imageURL: nil
    )
}

private func fixtureMovie(id: String = "one", title: String) -> Movie {
    Movie(
        id: ProviderReference(provider: "movie-fixture", value: id),
        title: title,
        releaseYear: nil,
        imageURL: nil
    )
}

private func releasePage(total: Int) -> ReleaseSearchPage {
    ReleaseSearchPage(offset: 0, total: total, candidates: [])
}

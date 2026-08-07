import CallupCore
import Foundation
import Testing
@testable import CallupPersistence

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

@Test func televisionReleaseSearchUsesTheSameStore() async throws {
    let store = try await ApplicationStore.inMemory()
    let upstream = ReleaseIndexerStub(page: releasePage(total: 2))
    let cached = CachedTelevisionReleaseIndexer(upstream: upstream, store: store)

    let first = try await cached.searchTelevision(
        query: "A Great Show",
        tvmazeID: "123",
        season: 1,
        episode: nil
    )
    await upstream.setPage(releasePage(total: 99))
    let second = try await cached.searchTelevision(
        query: "a great show",
        tvmazeID: "123",
        season: 1,
        episode: nil
    )

    #expect(first.total == 2)
    #expect(second.total == 2)
    #expect(await upstream.searchCount == 1)

    try await store.close()
}

private actor MetadataStub: TelevisionMetadataProvider {
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

    func episodes(for seriesID: ProviderReference) -> [TelevisionEpisode] {
        []
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
        season: Int?,
        episode: Int?
    ) -> ReleaseSearchPage {
        searchCount += 1
        return page
    }
}

private func series(title: String) -> TelevisionSeries {
    TelevisionSeries(
        id: ProviderReference(provider: "fixture", value: "one"),
        title: title,
        premieredYear: nil,
        status: nil,
        network: nil,
        imageURL: nil
    )
}

private func releasePage(total: Int) -> ReleaseSearchPage {
    ReleaseSearchPage(offset: 0, total: total, candidates: [])
}

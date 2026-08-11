import CallupCore
import Testing

@Test func metadataCatalogSearchesSuppliersAndPreservesTheirPriority() async throws {
    let first = MetadataSupplierStub(
        id: "first",
        results: [series(provider: "first", id: "1", title: "First")]
    )
    let second = MetadataSupplierStub(
        id: "second",
        results: [series(provider: "second", id: "2", title: "Second")]
    )
    let catalog = TelevisionMetadataCatalog(suppliers: [first, second])

    #expect(try await catalog.searchSeries(query: "example").map(\.title) == [
        "First", "Second",
    ])
}

@Test func metadataCatalogRoutesProviderReferencesToTheirSupplier() async throws {
    let expected = series(provider: "second", id: "2", title: "Second")
    let catalog = TelevisionMetadataCatalog(suppliers: [
        MetadataSupplierStub(id: "first", results: []),
        MetadataSupplierStub(id: "second", results: [expected]),
    ])

    #expect(try await catalog.series(for: expected.id) == expected)
    await #expect(throws: MetadataCatalogError.unsupportedReference(
        ProviderReference(provider: "missing", value: "1")
    )) {
        try await catalog.series(
            for: ProviderReference(provider: "missing", value: "1")
        )
    }
}

private struct MetadataSupplierStub: TelevisionMetadataSupplier {
    let metadataSupplier: MetadataSupplier
    let results: [TelevisionSeries]

    init(id: String, results: [TelevisionSeries]) {
        metadataSupplier = MetadataSupplier(
            id: id,
            displayName: id,
            supportedMediaKinds: [.televisionSeries, .televisionEpisode]
        )
        self.results = results
    }

    func searchSeries(query: String) -> [TelevisionSeries] {
        results
    }

    func series(for seriesID: ProviderReference) throws -> TelevisionSeries {
        guard let result = results.first(where: { $0.id == seriesID }) else {
            throw MetadataCatalogError.unsupportedReference(seriesID)
        }
        return result
    }

    func episodes(for seriesID: ProviderReference) -> [TelevisionEpisode] {
        []
    }
}

private func series(
    provider: String,
    id: String,
    title: String
) -> TelevisionSeries {
    TelevisionSeries(
        id: ProviderReference(provider: provider, value: id),
        title: title,
        premieredYear: nil,
        status: nil,
        network: nil,
        imageURL: nil
    )
}

public struct TelevisionMetadataCatalog: TelevisionMetadataProvider {
    private let suppliers: [any TelevisionMetadataSupplier]

    public init(suppliers: [any TelevisionMetadataSupplier]) {
        self.suppliers = suppliers
    }

    public func searchSeries(query: String) async throws -> [TelevisionSeries] {
        let indexed = try await withThrowingTaskGroup(
            of: (Int, [TelevisionSeries]).self,
            returning: [(Int, [TelevisionSeries])].self
        ) { group in
            for (index, supplier) in suppliers.enumerated() {
                group.addTask {
                    (index, try await supplier.searchSeries(query: query))
                }
            }

            var results: [(Int, [TelevisionSeries])] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }

        var seen: Set<ProviderReference> = []
        return indexed
            .sorted { $0.0 < $1.0 }
            .flatMap(\.1)
            .filter { seen.insert($0.id).inserted }
    }

    public func series(for seriesID: ProviderReference) async throws -> TelevisionSeries {
        try await supplier(for: seriesID).series(for: seriesID)
    }

    public func episodes(for seriesID: ProviderReference) async throws -> [TelevisionEpisode] {
        try await supplier(for: seriesID).episodes(for: seriesID)
    }

    private func supplier(
        for reference: ProviderReference
    ) throws -> any TelevisionMetadataSupplier {
        guard let supplier = suppliers.first(where: { $0.metadataSupplier.id == reference.provider })
        else {
            throw MetadataCatalogError.unsupportedReference(reference)
        }
        return supplier
    }
}

public struct MovieMetadataCatalog: MovieMetadataProvider {
    private let suppliers: [any MovieMetadataSupplier]

    public init(suppliers: [any MovieMetadataSupplier]) {
        self.suppliers = suppliers
    }

    public func searchMovies(query: String) async throws -> [Movie] {
        let indexed = try await withThrowingTaskGroup(
            of: (Int, [Movie]).self,
            returning: [(Int, [Movie])].self
        ) { group in
            for (index, supplier) in suppliers.enumerated() {
                group.addTask {
                    (index, try await supplier.searchMovies(query: query))
                }
            }

            var results: [(Int, [Movie])] = []
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

    public func movie(for movieID: ProviderReference) async throws -> Movie {
        try await supplier(for: movieID).movie(for: movieID)
    }

    private func supplier(for reference: ProviderReference) throws -> any MovieMetadataSupplier {
        guard let supplier = suppliers.first(where: { $0.metadataSupplier.id == reference.provider })
        else {
            throw MetadataCatalogError.unsupportedReference(reference)
        }
        return supplier
    }
}

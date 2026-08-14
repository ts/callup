import CallupCore
import Testing

@Test func movieMetadataCatalogSearchesAndRoutesSuppliers() async throws {
    let firstMovie = movie(provider: "first", id: "1", title: "First")
    let secondMovie = movie(provider: "second", id: "2", title: "Second")
    let catalog = MovieMetadataCatalog(suppliers: [
        MovieMetadataSupplierStub(id: "first", results: [firstMovie]),
        MovieMetadataSupplierStub(id: "second", results: [secondMovie]),
    ])

    #expect(try await catalog.searchMovies(query: "example") == [firstMovie, secondMovie])
    #expect(try await catalog.movie(for: secondMovie.id) == secondMovie)
    await #expect(throws: MetadataCatalogError.unsupportedReference(
        ProviderReference(provider: "missing", value: "1")
    )) {
        try await catalog.movie(for: ProviderReference(provider: "missing", value: "1"))
    }
}

private struct MovieMetadataSupplierStub: MovieMetadataSupplier {
    let metadataSupplier: MetadataSupplier
    let results: [Movie]

    init(id: String, results: [Movie]) {
        metadataSupplier = MetadataSupplier(
            id: id,
            displayName: id,
            supportedMediaKinds: [.movie]
        )
        self.results = results
    }

    func searchMovies(query: String) -> [Movie] {
        results
    }

    func movie(for movieID: ProviderReference) throws -> Movie {
        guard let result = results.first(where: { $0.id == movieID }) else {
            throw MetadataCatalogError.unsupportedReference(movieID)
        }
        return result
    }
}

private func movie(provider: String, id: String, title: String) -> Movie {
    Movie(
        id: ProviderReference(provider: provider, value: id),
        title: title,
        releaseYear: nil,
        imageURL: nil
    )
}

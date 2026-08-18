import CallupCore
import Foundation
import Testing
@testable import CallupTMDB

@Test func environmentTMDBCredentialOverridesTheBundledCredential() throws {
    let token = try #require(TMDBCredentialResolver.resolve(
        environment: ["CALLUP_TMDB_ACCESS_TOKEN": "environment-token"],
        bundled: "bundled-token"
    ))
    let request = try TMDBRequestBuilder.searchMovies(
        baseURL: #require(URL(string: "https://api.themoviedb.org/3")),
        token: token,
        query: "Alien"
    )

    #expect(request.value(forHTTPHeaderField: "authorization") == "Bearer environment-token")
}

@Test func configuredTMDBCredentialOverridesTheBundledCredential() throws {
    let token = try #require(TMDBCredentialResolver.resolve(
        environment: [:],
        configured: "configured-token",
        bundled: "bundled-token"
    ))
    let request = TMDBRequestBuilder.authentication(
        baseURL: try #require(URL(string: "https://api.themoviedb.org/3")),
        token: token
    )

    #expect(request.url?.path == "/3/authentication")
    #expect(request.value(forHTTPHeaderField: "authorization") == "Bearer configured-token")
}

@Test func bundledTMDBCredentialIsTheAutomaticFallback() {
    #expect(TMDBCredentialResolver.resolve(
        environment: [:],
        bundled: "bundled-token"
    ) != nil)
    #expect(TMDBCredentialResolver.resolve(environment: [:], bundled: nil) == nil)
}

@Test func buildsMovieSearchWithHeaderOnlyCredential() throws {
    let token = try TMDBAccessToken("fixture-token")
    let request = try TMDBRequestBuilder.searchMovies(
        baseURL: #require(URL(string: "https://api.themoviedb.org/3")),
        token: token,
        query: "The Apartment"
    )
    let components = try #require(
        request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
    )

    #expect(components.path == "/3/search/movie")
    #expect(components.queryItems?.first(where: { $0.name == "query" })?.value == "The Apartment")
    #expect(components.queryItems?.first(where: { $0.name == "include_adult" })?.value == "false")
    #expect(request.value(forHTTPHeaderField: "authorization") == "Bearer fixture-token")
    #expect(!request.url!.absoluteString.contains("fixture-token"))
    #expect(token.description == "<redacted>")
}

@Test func decodesMovieSearchIntoTheSharedDomain() throws {
    let data = Data(#"""
    {
      "page": 1,
      "results": [
        {
          "id": 284,
          "title": "The Apartment",
          "release_date": "1960-06-21",
          "poster_path": "/fixture.jpg"
        }
      ],
      "total_pages": 1,
      "total_results": 1
    }
    """#.utf8)

    #expect(try TMDBDecoder.decodeSearch(data) == [
        Movie(
            id: ProviderReference(provider: "tmdb", value: "284"),
            title: "The Apartment",
            releaseYear: 1960,
            releaseDate: "1960-06-21",
            imageURL: "https://image.tmdb.org/t/p/w342/fixture.jpg"
        )
    ])
}

@Test func decodesMovieDetailsWithCrossProviderIdentity() throws {
    let data = Data(#"""
    {
      "id": 284,
      "title": "The Apartment",
      "release_date": "1960-06-21",
      "poster_path": null,
      "imdb_id": "tt0053604"
    }
    """#.utf8)

    #expect(try TMDBDecoder.decodeMovie(data).imdbID == "tt0053604")
}

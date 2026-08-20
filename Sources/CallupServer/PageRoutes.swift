import Foundation
import Vapor

func registerPageRoutes(on application: Application) throws {
    let assets = try WebAssets()
    application.get { _ in indexResponse(assets.index.content) }
    application.get("lineup") { _ in indexResponse(assets.index.content) }
    application.get("quality") { _ in indexResponse(assets.index.content) }
    application.get("downloads") { _ in indexResponse(assets.index.content) }
    application.get("settings") { _ in indexResponse(assets.index.content) }
    application.get("assets", "app.css") { request in
        assetResponse(assets.css, contentType: "text/css; charset=utf-8", request: request)
    }
    application.get("assets", "app.js") { request in
        assetResponse(
            assets.javaScript,
            contentType: "text/javascript; charset=utf-8",
            request: request
        )
    }
}

private struct WebAssets {
    let index: WebAsset
    let css: WebAsset
    let javaScript: WebAsset

    init() throws {
        index = try Self.load("index", extension: "html")
        css = try Self.load("app", extension: "css")
        javaScript = try Self.load("app", extension: "js")
    }

    private static func load(_ name: String, extension fileExtension: String) throws -> WebAsset {
        let url = try resourceURL(name, extension: fileExtension)
        return WebAsset(content: try String(contentsOf: url, encoding: .utf8))
    }

    private static func resourceURL(_ name: String, extension fileExtension: String) throws -> URL {
        #if os(Linux)
        let executable = URL(fileURLWithPath: "/proc/self/exe").resolvingSymlinksInPath()
        let url = executable
            .deletingLastPathComponent()
            .appending(path: "Callup_CallupServer.resources/Web/\(name).\(fileExtension)")
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw WebAssetError.missing(url.path)
        }
        return url
        #else
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: fileExtension,
            subdirectory: "Web"
        ) else {
            throw WebAssetError.missing("\(name).\(fileExtension)")
        }
        return url
        #endif
    }
}

private struct WebAsset {
    let content: String
    let etag: String

    init(content: String) {
        self.content = content
        etag = "\"\(String(content.hashValue, radix: 16))\""
    }
}

private enum WebAssetError: Error, CustomStringConvertible {
    case missing(String)

    var description: String {
        switch self {
        case let .missing(path): "Missing web asset: \(path)"
        }
    }
}

private func indexResponse(_ index: String) -> Response {
    return Response(
        status: .ok,
        headers: [
            "cache-control": "no-store",
            "content-type": "text/html; charset=utf-8",
        ],
        body: .init(string: index)
    )
}

private func assetResponse(_ asset: WebAsset, contentType: String, request: Request) -> Response {
    if request.headers.first(name: "if-none-match") == asset.etag {
        return Response(status: .notModified, headers: ["etag": asset.etag])
    }
    return Response(
        status: .ok,
        headers: [
            "cache-control": "public, max-age=0, must-revalidate",
            "content-type": contentType,
            "etag": asset.etag,
        ],
        body: .init(string: asset.content)
    )
}

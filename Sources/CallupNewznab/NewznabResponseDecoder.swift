import CallupCore
import Foundation

public typealias NewznabPage = ReleaseSearchPage

public enum NewznabResponseError: Error, Equatable {
    case invalidXML
    case providerError(code: String, description: String)
    case missingIdentifier
    case missingTitle
}

public enum NewznabResponseDecoder {
    public static func decode(_ data: Data, provider: String) throws -> NewznabPage {
        let delegate = FeedParser(provider: provider)
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            if let error = delegate.error { throw error }
            throw NewznabResponseError.invalidXML
        }
        if let error = delegate.error { throw error }

        return NewznabPage(
            offset: delegate.offset,
            total: delegate.total,
            candidates: try delegate.items.map { try $0.candidate(provider: provider) }
        )
    }
}

private final class FeedParser: NSObject, XMLParserDelegate {
    let provider: String
    var offset = 0
    var total = 0
    var items: [ParsedItem] = []
    var error: NewznabResponseError?

    private var currentItem: ParsedItem?
    private var currentElement: String?
    private var text = ""

    init(provider: String) {
        self.provider = provider
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = qName ?? elementName
        currentElement = name
        text = ""

        switch name {
        case "item":
            currentItem = ParsedItem()
        case "newznab:response":
            offset = Int(attributeDict["offset"] ?? "") ?? 0
            total = Int(attributeDict["total"] ?? "") ?? 0
        case "newznab:attr":
            if let attributeName = attributeDict["name"], let value = attributeDict["value"] {
                currentItem?.attributes[attributeName, default: []].append(value)
            }
        case "error":
            error = .providerError(
                code: attributeDict["code"] ?? "unknown",
                description: attributeDict["description"] ?? "The indexer returned an error."
            )
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = qName ?? elementName
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if name == "title", currentItem != nil {
            currentItem?.title = value
        } else if name == "guid", currentItem != nil {
            currentItem?.guid = value
        } else if name == "pubDate", currentItem != nil {
            currentItem?.publishedAt = Self.parseDate(value)
        } else if name == "item", let item = currentItem {
            items.append(item)
            currentItem = nil
        }

        currentElement = nil
        text = ""
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.date(from: value)
    }
}

private struct ParsedItem {
    var title: String?
    var guid: String?
    var publishedAt: Date?
    var attributes: [String: [String]] = [:]

    func candidate(provider: String) throws -> ReleaseCandidate {
        guard let title, !title.isEmpty else { throw NewznabResponseError.missingTitle }
        guard let identifier = safeIdentifier else { throw NewznabResponseError.missingIdentifier }
        let parsedTitle = ReleaseTitleParser.parse(title)

        return ReleaseCandidate(
            id: ProviderReference(provider: provider, value: identifier),
            title: title,
            sizeBytes: attributes["size"]?.first.flatMap(Int64.init),
            publishedAt: publishedAt,
            coverage: reportedCoverage ?? parsedTitle.coverage,
            reportedTraits: ReportedReleaseTraits(
                videoCodec: attributes["video"]?.first ?? parsedTitle.traits.videoCodec,
                resolution: attributes["resolution"]?.first ?? parsedTitle.traits.resolution,
                source: attributes["source"]?.first ?? parsedTitle.traits.source
            ),
            reportedMediaIDs: reportedMediaIDs
        )
    }

    private var safeIdentifier: String? {
        if let value = attributes["guid"]?.first, !value.isEmpty { return value }
        guard let guid, !guid.isEmpty else { return nil }
        if let url = URL(string: guid), url.scheme != nil {
            let component = url.lastPathComponent
            return component.isEmpty ? nil : component
        }
        return guid
    }

    private var reportedCoverage: [CandidateCoverage]? {
        guard let season = attributes["season"]?.first.flatMap(Int.init) else { return nil }
        let episodes = attributes["episode", default: []].compactMap(Int.init)
        guard !episodes.isEmpty else { return nil }
        return [
            .init(
                scope: .televisionEpisode,
                seasonNumber: season,
                episodeNumbers: Array(Set(episodes)).sorted()
            )
        ]
    }

    private var reportedMediaIDs: [ProviderReference] {
        var ids: [ProviderReference] = []
        appendIdentifier(attributes["tvmazeid"]?.first, provider: "tvmaze", to: &ids)
        appendIdentifier(attributes["tvdbid"]?.first, provider: "thetvdb", to: &ids)
        appendIdentifier(
            attributes["imdbid"]?.first ?? attributes["imdb"]?.first,
            provider: "imdb",
            to: &ids
        )
        return ids
    }

    private func appendIdentifier(
        _ value: String?,
        provider: String,
        to ids: inout [ProviderReference]
    ) {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return }
        ids.append(ProviderReference(provider: provider, value: value))
    }
}

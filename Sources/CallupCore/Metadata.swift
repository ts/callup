public struct MetadataSupplier: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let supportedMediaKinds: Set<MediaKind>

    public init(
        id: String,
        displayName: String,
        supportedMediaKinds: Set<MediaKind>
    ) {
        self.id = id
        self.displayName = displayName
        self.supportedMediaKinds = supportedMediaKinds
    }
}

public enum MetadataCatalogError: Error, Equatable {
    case unsupportedReference(ProviderReference)
}

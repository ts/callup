import CallupCore
import CallupDownloadClients
import CallupPersistence
import CallupUpdates
import Vapor

func registerRoutes(
    on application: Application,
    store: ApplicationStore,
    connectionSettings: ConnectionSettingsStore,
    metadata: TelevisionMetadataCatalog,
    movieMetadata: ConfiguredMovieMetadataProvider,
    downloadClientProbe: DownloadClientProbe,
    sabnzbdClient: SABnzbdClient,
    library: LibraryInventory,
    updates: CallupUpdateService,
    revision: String
) {
    registerPageRoutes(on: application)
    CallupServer.registerAPIRoutes(
        on: application,
        store: store,
        connectionSettings: connectionSettings,
        metadata: metadata,
        movieMetadata: movieMetadata,
        downloadClientProbe: downloadClientProbe,
        sabnzbdClient: sabnzbdClient,
        library: library,
        updates: updates,
        revision: revision
    )
}

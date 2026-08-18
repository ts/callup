import Vapor

func registerPageRoutes(on application: Application) {
    application.get { _ in indexResponse() }
    application.get("lineup") { _ in indexResponse() }
    application.get("downloads") { _ in indexResponse() }
    application.get("settings") { _ in indexResponse() }
}

private func indexResponse() -> Response {
    Response(
        status: .ok,
        headers: ["content-type": "text/html; charset=utf-8"],
        body: .init(string: indexHTML)
    )
}

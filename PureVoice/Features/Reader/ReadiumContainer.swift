import Foundation
@preconcurrency import ReadiumShared
@preconcurrency import ReadiumStreamer

@MainActor
final class ReadiumContainer {
    func openPublication(at fileURL: URL) async throws -> Publication {
        let httpClient: HTTPClient = DefaultHTTPClient()
        let assetRetriever = AssetRetriever(httpClient: httpClient)
        let publicationOpener = PublicationOpener(
            parser: DefaultPublicationParser(
                httpClient: httpClient,
                assetRetriever: assetRetriever,
                pdfFactory: DefaultPDFDocumentFactory()
            ),
            contentProtections: []
        )
        guard let absoluteURL = FileURL(url: fileURL) else {
            throw PublicationServiceError.invalidFileURL
        }
        let asset = try await assetRetriever.retrieve(url: absoluteURL).get()
        let publication = try await publicationOpener.open(
            asset: asset,
            allowUserInteraction: false,
            sender: nil
        ).get()
        return publication
    }
}

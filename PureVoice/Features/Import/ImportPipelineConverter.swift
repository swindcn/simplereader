import Foundation

struct ImportPipelineConverter: CanonicalPublicationConverting, @unchecked Sendable {
    private let txtConverter: any CanonicalPublicationConverting
    private let fileManager: FileManager

    init(
        txtConverter: any CanonicalPublicationConverting = TXTCanonicalPublicationConverter(),
        fileManager: FileManager = .default
    ) {
        self.txtConverter = txtConverter
        self.fileManager = fileManager
    }

    func convert(
        originalURL: URL,
        format: BookFormat,
        suggestedTitle: String,
        destinationURL: URL
    ) async throws {
        switch format {
        case .txt:
            try await txtConverter.convert(
                originalURL: originalURL,
                format: format,
                suggestedTitle: suggestedTitle,
                destinationURL: destinationURL
            )
        case .epub:
            try Task.checkCancellation()
            try copyEPUB(from: originalURL, to: destinationURL)
        case .mobi:
            throw TXTConversionError.unsupportedFormat(format)
        }
    }

    private func copyEPUB(from originalURL: URL, to destinationURL: URL) throws {
        let directory = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let temporaryURL = directory.appendingPathComponent(".publication-\(UUID().uuidString).epub")
        do {
            try fileManager.copyItem(at: originalURL, to: temporaryURL)
            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            }
        } catch {
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try? fileManager.removeItem(at: temporaryURL)
            }
            throw error
        }
    }
}

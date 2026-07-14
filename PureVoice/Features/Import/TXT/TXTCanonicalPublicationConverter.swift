import Foundation

enum TXTConversionError: Error, Equatable, LocalizedError {
    case unsupportedFormat(BookFormat)
    case unsupportedFileExtension(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat, .unsupportedFileExtension:
            return "TXT 转换器仅支持 TXT 文件。"
        }
    }
}

struct TXTCanonicalPublicationConverter: CanonicalPublicationConverting {
    private let decoder = TXTDecoder()
    private let parser = ChapterParser()
    private let builder = EPUBBuilder()

    func convert(originalURL: URL, format: BookFormat, destinationURL: URL) async throws {
        guard format == .txt else { throw TXTConversionError.unsupportedFormat(format) }
        let fileExtension = originalURL.pathExtension.lowercased()
        guard fileExtension == "txt" else {
            throw TXTConversionError.unsupportedFileExtension(fileExtension)
        }
        let text = try decoder.decode(contentsOf: originalURL)
        let chapters = parser.parse(text)
        let title = originalURL.deletingPathExtension().lastPathComponent
        try await builder.build(chapters: chapters, title: title, destinationURL: destinationURL)
    }
}

import Foundation

enum TXTConversionError: Error, Equatable, LocalizedError {
    case unsupportedFormat(BookFormat)
    case fileTooLarge(maxBytes: Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "TXT 转换器仅支持 TXT 文件。"
        case let .fileTooLarge(maxBytes):
            return "TXT 文件超过本地转换上限（\(maxBytes) 字节）。"
        }
    }
}

struct TXTCanonicalPublicationConverter: CanonicalPublicationConverting {
    static let maximumSourceBytes = 16 * 1_024 * 1_024

    private let decoder = TXTDecoder()
    private let parser = ChapterParser()
    private let builder = EPUBBuilder()

    func convert(originalURL: URL, format: BookFormat, suggestedTitle: String, destinationURL: URL) async throws {
        guard format == .txt else { throw TXTConversionError.unsupportedFormat(format) }
        try Task.checkCancellation()
        let resourceValues = try originalURL.resourceValues(forKeys: [.fileSizeKey])
        if let size = resourceValues.fileSize, size > Self.maximumSourceBytes {
            throw TXTConversionError.fileTooLarge(maxBytes: Self.maximumSourceBytes)
        }
        try Task.checkCancellation()
        let data = try Data(contentsOf: originalURL, options: [.mappedIfSafe])
        guard data.count <= Self.maximumSourceBytes else {
            throw TXTConversionError.fileTooLarge(maxBytes: Self.maximumSourceBytes)
        }
        let text = try decoder.decode(data: data)
        try Task.checkCancellation()
        let chapters = parser.parse(text)
        try Task.checkCancellation()
        try await builder.build(chapters: chapters, title: suggestedTitle, destinationURL: destinationURL)
    }
}

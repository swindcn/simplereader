import Foundation

struct BookFormatDetector: Sendable {
    let maximumHeaderBytes: Int

    init(maximumHeaderBytes: Int = 68) {
        self.maximumHeaderBytes = max(68, maximumHeaderBytes)
    }

    func detect(at copiedFileURL: URL) throws -> BookFormat {
        let fileExtension = copiedFileURL.pathExtension.lowercased()
        if isMOBIPendingApprovalExtension(fileExtension) {
            throw BookFormatDetectionError.mobiPendingLegalApproval
        }

        let header: Data
        do {
            let handle = try FileHandle(forReadingFrom: copiedFileURL)
            defer { try? handle.close() }
            header = try handle.read(upToCount: maximumHeaderBytes) ?? Data()
        } catch {
            throw BookFormatDetectionError.unreadableFile(copiedFileURL.path)
        }

        if hasZIPSignature(header) {
            return .epub
        }
        if header.count >= 68,
           header.subdata(in: 60..<68) == Data("BOOKMOBI".utf8) {
            throw BookFormatDetectionError.mobiPendingLegalApproval
        }

        switch fileExtension {
        case "txt":
            return .txt
        case "epub":
            return .epub
        case "mobi", "azw", "azw3":
            throw BookFormatDetectionError.mobiPendingLegalApproval
        default:
            throw BookFormatDetectionError.unsupportedExtension(fileExtension)
        }
    }

    private func isMOBIPendingApprovalExtension(_ fileExtension: String) -> Bool {
        fileExtension == "mobi" || fileExtension == "azw" || fileExtension == "azw3"
    }

    private func hasZIPSignature(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let prefix = Array(data.prefix(4))
        return prefix == [0x50, 0x4B, 0x03, 0x04]
            || prefix == [0x50, 0x4B, 0x05, 0x06]
            || prefix == [0x50, 0x4B, 0x07, 0x08]
    }
}

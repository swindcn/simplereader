import CoreFoundation
import Foundation

enum TXTDecodingError: Error, Equatable, LocalizedError {
    case emptyFile
    case unsupportedEncoding

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "TXT 文件为空。"
        case .unsupportedEncoding:
            return "无法识别 TXT 文件的字符编码。"
        }
    }
}

struct TXTDecoder: Sendable {
    func decode(data: Data) throws -> String {
        guard !data.isEmpty else { throw TXTDecodingError.emptyFile }

        if let text = decodeUTF8(data), isReadable(text) {
            return stripBOM(text)
        }
        if let text = decodeUTF16(data), isReadable(text) {
            return stripBOM(text)
        }
        if let text = decode(data, cfEncoding: CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)), isReadable(text) {
            return text
        }
        if let text = decode(data, cfEncoding: CFStringEncoding(CFStringEncodings.GBK_95.rawValue)), isReadable(text) {
            return text
        }
        throw TXTDecodingError.unsupportedEncoding
    }

    func decode(contentsOf url: URL) throws -> String {
        try decode(data: Data(contentsOf: url))
    }

    private func decodeUTF8(_ data: Data) -> String? {
        String(data: data, encoding: .utf8)
    }

    private func decodeUTF16(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(2))
        if bytes == [0xFF, 0xFE] {
            return String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        }
        if bytes == [0xFE, 0xFF] {
            return String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        }

        guard data.count.isMultiple(of: 2), let encoding = utf16EncodingSignal(data) else { return nil }
        guard let text = String(data: data, encoding: encoding),
              text.data(using: encoding, allowLossyConversion: false) == data,
              isReadable(text) else { return nil }
        return text
    }

    private func utf16EncodingSignal(_ data: Data) -> String.Encoding? {
        var evenNULs = 0
        var oddNULs = 0
        for (index, byte) in data.enumerated() where byte == 0 {
            if index.isMultiple(of: 2) { evenNULs += 1 } else { oddNULs += 1 }
        }
        let pairs = max(1, data.count / 2)
        let dominant = max(evenNULs, oddNULs)
        guard Double(dominant) / Double(pairs) >= 0.2,
              min(evenNULs, oddNULs) * 4 <= dominant else { return nil }
        return evenNULs > oddNULs ? .utf16BigEndian : .utf16LittleEndian
    }

    private func decode(_ data: Data, cfEncoding: CFStringEncoding) -> String? {
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        guard nsEncoding != UInt(kCFStringEncodingInvalidId) else { return nil }
        return String(data: data, encoding: String.Encoding(rawValue: nsEncoding))
    }

    private func isReadable(_ text: String) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let scalars = text.unicodeScalars
        guard !scalars.isEmpty else { return false }
        var invalid = 0
        for scalar in scalars {
            if scalar.value == 0 || scalar.value == 0xFFFD || isDisallowedControl(scalar.value) {
                invalid += 1
            }
        }
        return Double(invalid) / Double(scalars.count) <= 0.01
    }

    private func isDisallowedControl(_ value: UInt32) -> Bool {
        (value < 0x20 && value != 0x09 && value != 0x0A && value != 0x0D)
            || (value >= 0x7F && value <= 0x9F)
    }

    private func stripBOM(_ text: String) -> String {
        text.first == "\u{FEFF}" ? String(text.dropFirst()) : text
    }
}

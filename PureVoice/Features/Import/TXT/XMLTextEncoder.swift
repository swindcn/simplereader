import Foundation

struct XMLTextEncoder: Sendable {
    func encode(_ value: String) -> String {
        var output = ""
        output.reserveCapacity(value.utf8.count)
        for scalar in value.unicodeScalars {
            guard isLegalXMLScalar(scalar.value) else {
                output.append("&#xFFFD;")
                continue
            }
            switch scalar {
            case "&": output.append("&amp;")
            case "<": output.append("&lt;")
            case ">": output.append("&gt;")
            case "\"": output.append("&quot;")
            case "'": output.append("&apos;")
            default: output.unicodeScalars.append(scalar)
            }
        }
        return output
    }

    private func isLegalXMLScalar(_ value: UInt32) -> Bool {
        value == 0x09 || value == 0x0A || value == 0x0D
            || (value >= 0x20 && value <= 0xD7FF)
            || (value >= 0xE000 && value <= 0xFFFD)
            || (value >= 0x10000 && value <= 0x10FFFF)
    }
}

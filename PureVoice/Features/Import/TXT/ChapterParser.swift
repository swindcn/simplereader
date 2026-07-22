import Foundation

struct ChapterParser: Sendable {
    private static let chineseHeading = try! NSRegularExpression(
        pattern: #"^\s*(?:[0-9０-９]+\s*[\.．、:：]\s*)?第\s*(?:[0-9０-９]+|[零〇一二三四五六七八九十百千万两]+)\s*[章节回卷部篇](?:\s*[:：\-—]?\s*.*)?\s*$"#
    )
    private static let englishHeading = try! NSRegularExpression(
        pattern: #"^\s*chapter\s+[0-9]+(?:\s*[:：\-—]\s*.*|\s+.*)?\s*$"#,
        options: [.caseInsensitive]
    )

    func parse(_ text: String) -> [Chapter] {
        let lines = normalizedLines(text)
        var parsed: [(title: String, lines: [String])] = []
        var currentTitle: String?
        var currentLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if isHeading(trimmed) {
                if currentTitle != nil || containsContent(currentLines) {
                    parsed.append((currentTitle ?? "序章", normalizedBodyLines(currentLines)))
                }
                currentTitle = trimmed
                currentLines = []
            } else {
                currentLines.append(trimmed)
            }
        }

        if currentTitle != nil || containsContent(currentLines) {
            parsed.append((currentTitle ?? "正文", normalizedBodyLines(currentLines)))
        }
        if parsed.isEmpty {
            return [Chapter(index: 0, title: "正文", body: "")]
        }
        return parsed.enumerated().map { offset, item in
            Chapter(index: offset, title: item.title, body: item.lines.joined(separator: "\n"))
        }
    }

    private func normalizedLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    private func normalizedBodyLines(_ lines: [String]) -> [String] {
        var output: [String] = []
        for line in lines {
            if line.isEmpty {
                if !output.isEmpty && output.last != "" { output.append("") }
            } else {
                output.append(line)
            }
        }
        while output.last == "" { output.removeLast() }
        return output
    }

    private func containsContent(_ lines: [String]) -> Bool {
        lines.contains { !$0.isEmpty }
    }

    private func isHeading(_ line: String) -> Bool {
        guard !line.isEmpty, line.count <= 80 else { return false }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return Self.chineseHeading.firstMatch(in: line, range: range) != nil
            || Self.englishHeading.firstMatch(in: line, range: range) != nil
    }
}

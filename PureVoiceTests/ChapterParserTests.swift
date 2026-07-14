import XCTest
@testable import PureVoice

final class ChapterParserTests: XCTestCase {
    private let parser = ChapterParser()

    func testSplitsAnchoredChineseAndEnglishHeadingsAndKeepsPreface() {
        let text = """
        序言内容

        第十二章 重逢
        第一段
        这一章节奏很好
        他说第十二章很动人

        第 12 章
        第二段

        cHaPtEr 13 The Return
        third
        """
        let chapters = parser.parse(text)
        XCTAssertEqual(chapters.map(\.title), ["序章", "第十二章 重逢", "第 12 章", "cHaPtEr 13 The Return"])
        XCTAssertEqual(chapters[0].body, "序言内容")
        XCTAssertTrue(chapters[1].body.contains("这一章节奏很好"))
        XCTAssertTrue(chapters[1].body.contains("他说第十二章很动人"))
    }

    func testSupportsTraditionalUnitsAndRequiresAChapterNumber() {
        let chapters = parser.parse("第一回 开场\nA\n第二卷 风云\nB\n第三部\nC\n第四篇 终\nD\n这一章节奏很好")
        XCTAssertEqual(chapters.count, 4)
        XCTAssertEqual(chapters.last?.body, "D\n这一章节奏很好")
    }

    func testCreatesSingleBodyChapterWhenThereAreNoHeadings() {
        XCTAssertEqual(parser.parse("第一段\r\n\r\n\r\n第二段  \r尾声"), [
            Chapter(index: 0, title: "正文", body: "第一段\n\n第二段\n尾声")
        ])
    }

    func testAcceptsCompactChineseAndPunctuatedEnglishHeadings() {
        let chapters = parser.parse("第一章重逢\nA\nChapter 12: Return\nB\nChapter 13 - Again\nC")
        XCTAssertEqual(chapters.map(\.title), ["第一章重逢", "Chapter 12: Return", "Chapter 13 - Again"])
    }

    func testRejectsOverlongHeadingLikeSentences() {
        let longTail = String(repeating: "这是一句很长的正文", count: 10)
        XCTAssertEqual(parser.parse("第一章 \(longTail)").map(\.title), ["正文"])
    }
}

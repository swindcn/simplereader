import XCTest
@testable import PureVoice

final class UserFacingErrorTests: XCTestCase {
    func testImportFailuresMapToStableChineseRecoveryWithoutRawFrameworkText() {
        let cases: [(ImportFailure, String, String, String)] = [
            (.openFailed("The operation couldn't be completed. ZIPFoundation.ArchiveError error 1."),
             "书籍文件损坏",
             "这本书无法打开，文件可能不完整或已损坏。请重新获取文件后再导入。",
             "重新选择文件"),
            (.openFailed("ContentProtectionSchemeNotSupportedError"),
             "暂不支持受保护书籍",
             "这本书受 DRM 或密码保护，当前版本无法离线打开。",
             "换一本无保护文件"),
            (.unsupported,
             "不支持该格式",
             "当前版本支持 TXT 和 EPUB，请选择受支持的文件。",
             "选择 TXT 或 EPUB"),
            (.convertFailed("TXTDecodingError.unsupportedEncoding"),
             "无法识别文本编码",
             "这份 TXT 的字符编码暂不支持。请转换为 UTF-8、UTF-16、GBK 或 GB18030 后再导入。",
             "转换编码后重试"),
            (.outOfSpace,
             "存储空间不足",
             "设备空间不足，无法保存这本书。请释放空间后重试。",
             "释放空间后重试"),
            (.interrupted,
             "导入已中断",
             "上次导入在完成前中断，原文件已保留，请重新导入。",
             "重新导入"),
            (.cancelled,
             "已取消导入",
             "导入已取消，原文件没有被删除。",
             "重新导入")
        ]

        for (failure, title, message, recoveryAction) in cases {
            let mapped = UserFacingError(importFailure: failure)
            XCTAssertEqual(mapped.title, title)
            XCTAssertEqual(mapped.message, message)
            XCTAssertEqual(mapped.recoveryAction, recoveryAction)
            XCTAssertFalse(mapped.message.contains("operation couldn't be completed"))
            XCTAssertFalse(mapped.message.contains("ZIPFoundation"))
            XCTAssertFalse(mapped.message.contains("ContentProtection"))
            XCTAssertFalse(mapped.message.contains("TXTDecodingError"))
            XCTAssertEqual(mapped.accessibilityAnnouncement, "\(title)，\(message)")
        }
    }

    func testReaderAndListeningErrorsUseChineseRecoveryMessages() {
        let readium = UserFacingError.readerOpenFailure(PublicationServiceError.invalidPublication)
        XCTAssertEqual(readium.title, "无法打开这本书")
        XCTAssertEqual(readium.message, "书籍文件可能已损坏或不完整。请重新导入原文件。")
        XCTAssertEqual(readium.recoveryAction, "重新导入")

        let interruption = UserFacingError.audioInterruptionRecoveryFailed
        XCTAssertEqual(interruption.title, "播放被中断")
        XCTAssertEqual(interruption.message, "系统音频中断后未能自动恢复，请点击播放继续。")
        XCTAssertEqual(interruption.recoveryAction, "点击播放")
    }
}

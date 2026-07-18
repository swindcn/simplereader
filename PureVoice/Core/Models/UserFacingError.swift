import Foundation

struct UserFacingError: Equatable, Codable, Sendable {
    let title: String
    let message: String
    let recoveryAction: String

    var accessibilityAnnouncement: String { "\(title)，\(message)" }

    init(title: String, message: String, recoveryAction: String) {
        self.title = title
        self.message = message
        self.recoveryAction = recoveryAction
    }

    init(importFailure: ImportFailure) {
        switch importFailure {
        case .cancelled:
            self = .init(
                title: "已取消导入",
                message: "导入已取消，原文件没有被删除。",
                recoveryAction: "重新导入"
            )
        case .unsupported:
            self = .unsupportedFormat
        case .mobiPendingLegalApproval:
            self = .init(
                title: "暂不支持 MOBI",
                message: "MOBI、AZW 和 AZW3 导入正在等待许可证审批，当前版本仅支持 TXT 和 EPUB。",
                recoveryAction: "选择 TXT 或 EPUB"
            )
        case .tooLarge:
            self = .init(
                title: "文件过大",
                message: "文件超过 250 MB 限制，当前版本无法导入。",
                recoveryAction: "选择较小文件"
            )
        case .outOfSpace:
            self = .outOfSpace
        case let .copyFailed(message):
            self = Self.copyFailure(rawMessage: message)
        case let .detectFailed(message):
            self = Self.messageIndicatesUnsupportedEncoding(message) ? .unsupportedEncoding : .unsupportedFormat
        case let .convertFailed(message):
            self = Self.messageIndicatesUnsupportedEncoding(message)
                ? .unsupportedEncoding
                : .init(
                    title: "转换失败",
                    message: "这本书暂时无法转换，原文件已保留。请稍后重试或换一个文件。",
                    recoveryAction: "重试导入"
                )
        case let .openFailed(message):
            self = Self.openFailure(rawMessage: message)
        case .saveFailed:
            self = .init(
                title: "保存失败",
                message: "书籍已处理完成，但保存到本地书库失败。请重试。",
                recoveryAction: "重试导入"
            )
        case .cleanupFailed:
            self = .init(
                title: "导入清理失败",
                message: "导入未完成，原文件已保留。请稍后重试。",
                recoveryAction: "重试导入"
            )
        }
    }

    static let unsupportedFormat = UserFacingError(
        title: "不支持该格式",
        message: "当前版本支持 TXT 和 EPUB，请选择受支持的文件。",
        recoveryAction: "选择 TXT 或 EPUB"
    )

    static let unsupportedEncoding = UserFacingError(
        title: "无法识别文本编码",
        message: "这份 TXT 的字符编码暂不支持。请转换为 UTF-8、UTF-16、GBK 或 GB18030 后再导入。",
        recoveryAction: "转换编码后重试"
    )

    static let outOfSpace = UserFacingError(
        title: "存储空间不足",
        message: "设备空间不足，无法保存这本书。请释放空间后重试。",
        recoveryAction: "释放空间后重试"
    )

    static let importInterrupted = UserFacingError(
        title: "导入已中断",
        message: "上次导入在完成前中断，原文件已保留，请重新导入。",
        recoveryAction: "重新导入"
    )

    static let audioInterruptionRecoveryFailed = UserFacingError(
        title: "播放被中断",
        message: "系统音频中断后未能自动恢复，请点击播放继续。",
        recoveryAction: "点击播放"
    )

    static func readerOpenFailure(_ error: Error) -> UserFacingError {
        if let publicationError = error as? PublicationServiceError {
            switch publicationError {
            case .protectedPublication:
                return protectedPublication
            case .invalidFileURL:
                return .init(
                    title: "无法访问文件",
                    message: "这本书的本地文件不可访问。请确认文件仍在设备上，或重新导入。",
                    recoveryAction: "重新导入"
                )
            case .invalidPublication:
                return .init(
                    title: "无法打开这本书",
                    message: "书籍文件可能已损坏或不完整。请重新导入原文件。",
                    recoveryAction: "重新导入"
                )
            case .coverPersistenceFailed:
                return .init(
                    title: "封面保存失败",
                    message: "书籍可以继续阅读，但封面暂时无法保存。",
                    recoveryAction: "继续阅读"
                )
            case .invalidReadingPosition:
                return .init(
                    title: "阅读位置失效",
                    message: "上次阅读位置无法恢复，已从书首开始。",
                    recoveryAction: "继续阅读"
                )
            }
        }
        return .init(
            title: "无法打开这本书",
            message: "阅读器无法打开当前文件。请重新导入原文件。",
            recoveryAction: "重新导入"
        )
    }

    private static let protectedPublication = UserFacingError(
        title: "暂不支持受保护书籍",
        message: "这本书受 DRM 或密码保护，当前版本无法离线打开。",
        recoveryAction: "换一本无保护文件"
    )

    private static func copyFailure(rawMessage: String) -> UserFacingError {
        messageIndicatesOutOfSpace(rawMessage)
            ? .outOfSpace
            : .init(
                title: "复制失败",
                message: "无法复制所选文件。请确认文件可访问后重试。",
                recoveryAction: "重新选择文件"
            )
    }

    private static func openFailure(rawMessage: String) -> UserFacingError {
        if messageIndicatesProtection(rawMessage) {
            return protectedPublication
        }
        return .init(
            title: "书籍文件损坏",
            message: "这本书无法打开，文件可能不完整或已损坏。请重新获取文件后再导入。",
            recoveryAction: "重新选择文件"
        )
    }

    private static func messageIndicatesProtection(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return lowercased.contains("contentprotection")
            || lowercased.contains("drm")
            || lowercased.contains("protected")
            || lowercased.contains("密码")
            || lowercased.contains("受保护")
    }

    private static func messageIndicatesUnsupportedEncoding(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return lowercased.contains("encoding")
            || lowercased.contains("txtdecodingerror")
            || lowercased.contains("字符编码")
    }

    private static func messageIndicatesOutOfSpace(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return lowercased.contains("space")
            || lowercased.contains("容量")
            || lowercased.contains("空间")
    }
}

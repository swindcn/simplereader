import Foundation

enum ImportCoordinatorError: Error, Equatable, Sendable {
    case importInProgress
}

enum ImportFailure: Equatable, Sendable {
    case cancelled
    case unsupported
    case mobiPendingLegalApproval
    case tooLarge
    case outOfSpace
    case copyFailed(String)
    case detectFailed(String)
    case convertFailed(String)
    case openFailed(String)
    case saveFailed(String)
    case cleanupFailed(String)

    var userMessage: String {
        switch self {
        case .cancelled:
            return "已取消导入"
        case .unsupported:
            return "不支持该文件格式"
        case .mobiPendingLegalApproval:
            return "MOBI、AZW 和 AZW3 导入正在等待许可证审批，当前版本仅支持 TXT 和 EPUB。"
        case .tooLarge:
            return "文件超过 250 MB 限制"
        case .outOfSpace:
            return "存储空间不足"
        case let .copyFailed(message):
            return "复制文件失败：\(message)"
        case let .detectFailed(message):
            return "识别文件格式失败：\(message)"
        case let .convertFailed(message):
            return "转换书籍失败：\(message)"
        case let .openFailed(message):
            return "打开书籍失败：\(message)"
        case let .saveFailed(message):
            return "保存书籍失败：\(message)"
        case let .cleanupFailed(message):
            return "清理导入文件失败：\(message)"
        }
    }
}

enum BookFormatDetectionError: Error, Equatable, Sendable {
    case unsupportedExtension(String)
    case mobiPendingLegalApproval
    case unreadableFile(String)
}

extension BookFormatDetectionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .unsupportedExtension(fileExtension):
            let displayExtension = fileExtension.isEmpty ? "无扩展名" : fileExtension
            return "不支持的文件格式：\(displayExtension)"
        case .mobiPendingLegalApproval:
            return "MOBI、AZW 和 AZW3 导入正在等待许可证审批，当前版本仅支持 TXT 和 EPUB。"
        case let .unreadableFile(path):
            return "无法读取文件：\(path)"
        }
    }
}

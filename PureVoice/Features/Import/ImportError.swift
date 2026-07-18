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
        UserFacingError(importFailure: self).message
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

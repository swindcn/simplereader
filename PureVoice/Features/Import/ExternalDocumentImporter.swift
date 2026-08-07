import SwiftUI

@MainActor
final class ExternalDocumentImporter: ObservableObject {
    @Published private(set) var error: UserFacingError?

    private let importCoordinator: ImportCoordinator

    init(importCoordinator: ImportCoordinator) {
        self.importCoordinator = importCoordinator
    }

    func open(_ url: URL) async {
        error = nil
        do {
            try await importCoordinator.importBook(from: url)
            if case let .failed(failure) = importCoordinator.state {
                error = UserFacingError(importFailure: failure)
            }
        } catch {
            self.error = UserFacingError(
                title: "导入失败",
                message: "无法从其他应用打开这个文件。请稍后重试，或换用 TXT、EPUB 文件。",
                recoveryAction: "选择 TXT 或 EPUB"
            )
        }
    }

    func dismissError() {
        error = nil
    }
}

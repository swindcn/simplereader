import SwiftUI

@main
struct PureVoiceApp: App {
    init() {
        LibraryNavigationBarStyle.apply()
    }

    var body: some Scene {
        WindowGroup {
            AppBootstrapView()
        }
    }

    @MainActor
    fileprivate static func makeDebugDependenciesIfRequested() -> AppDependencies? {
#if DEBUG
        if let readerPath = ProcessInfo.processInfo.environment["PUREVOICE_UI_TEST_READER_EPUB"] {
            let fileURL = URL(fileURLWithPath: readerPath)
            let book = seededBook(
                "99999999-9999-9999-9999-999999999999",
                "无障碍阅读示例",
                "示例作者",
                0,
                500,
                canonicalFileURL: fileURL
            )
            return makeDebugDependencies(books: [book])
        }
        if ProcessInfo.processInfo.environment["PUREVOICE_UI_TEST_LIBRARY_SEED"] == "1" {
            return makeDebugDependencies(books: uiTestBooks)
        }
#endif
        return nil
    }

#if DEBUG
    @MainActor
    private static func makeDebugDependencies(books: [Book]) -> AppDependencies? {
        do {
            return AppDependencies.make(
                repository: InMemoryBookRepository(books: books),
                fileStore: try BookFileStore()
            )
        } catch {
            let fallbackRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("PureVoice-Debug", isDirectory: true)
            guard let fileStore = try? BookFileStore(applicationSupportRoot: fallbackRoot) else {
                return nil
            }
            return AppDependencies.make(repository: InMemoryBookRepository(books: books), fileStore: fileStore)
        }
    }

    private static let uiTestBooks: [Book] = [
        seededBook("11111111-1111-1111-1111-111111111111", "活着", "余华", 0.35, 400),
        seededBook("22222222-2222-2222-2222-222222222222", "许三观卖血记", "余华", 0.62, 300),
        seededBook("33333333-3333-3333-3333-333333333333", "围城", "钱钟书", 0.12, 200),
        seededBook("44444444-4444-4444-4444-444444444444", "平凡的世界", "路遥", 1, 100)
    ]

    private static func seededBook(
        _ id: String,
        _ title: String,
        _ author: String,
        _ progression: Double,
        _ openedAt: TimeInterval,
        canonicalFileURL: URL? = nil
    ) -> Book {
        let id = UUID(uuidString: id)!
        return Book(
            id: id,
            title: title,
            author: author,
            format: .epub,
            originalFileURL: URL(fileURLWithPath: "/tmp/\(id)/original.epub"),
            canonicalFileURL: canonicalFileURL ?? URL(fileURLWithPath: "/tmp/\(id)/publication.epub"),
            coverFileURL: nil,
            position: ReadingPosition(href: "chapter.xhtml", progression: progression),
            lastOpenedAt: Date(timeIntervalSince1970: openedAt),
            createdAt: Date(timeIntervalSince1970: openedAt)
        )
    }
#endif
}

private struct AppBootstrapView: View {
    @State private var dependencies: AppDependencies?
    @State private var startupError: Error?

    var body: some View {
        Group {
            if let dependencies {
                RootTabView(
                    repository: dependencies.repository,
                    importCoordinator: dependencies.importCoordinator,
                    libraryRefresh: dependencies.libraryRefresh
                )
            } else if let startupError {
                FatalStartupView(error: startupError)
            } else {
                ProgressView("正在启动 PureVoice")
            }
        }
        .task {
            guard dependencies == nil, startupError == nil else { return }
            if let debugDependencies = PureVoiceApp.makeDebugDependenciesIfRequested() {
                dependencies = debugDependencies
                return
            }
            do {
                dependencies = try await AppDependencies.makeProduction()
            } catch {
                startupError = error
            }
        }
    }
}

private struct FatalStartupView: View {
    let error: Error

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("无法启动 PureVoice")
                .font(.title3.bold())
            Text("本地书库初始化失败，请稍后重试。")
                .multilineTextAlignment(.center)
            Text(error.localizedDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

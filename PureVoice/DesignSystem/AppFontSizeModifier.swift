import SwiftUI

extension AppFontSize {
    var dynamicTypeSize: DynamicTypeSize? {
        switch self {
        case .small:
            .medium
        case .medium:
            .large
        case .large:
            .xLarge
        case .extraLarge:
            .xxLarge
        }
    }
}

private struct AppFontSizeEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppFontSize = .extraLarge
}

extension EnvironmentValues {
    var appFontSize: AppFontSize {
        get { self[AppFontSizeEnvironmentKey.self] }
        set { self[AppFontSizeEnvironmentKey.self] = newValue }
    }
}

private struct AppLanguageEnvironmentKey: EnvironmentKey {
    static let defaultValue: EffectiveAppLanguage = AppLanguage.system.effectiveLanguage
}

extension EnvironmentValues {
    var appLanguage: EffectiveAppLanguage {
        get { self[AppLanguageEnvironmentKey.self] }
        set { self[AppLanguageEnvironmentKey.self] = newValue }
    }

    var appStrings: AppStrings {
        AppStrings(language: appLanguage)
    }
}

extension View {
    @ViewBuilder
    func appFontSize(_ size: AppFontSize) -> some View {
        if let dynamicTypeSize = size.dynamicTypeSize {
            self
                .environment(\.appFontSize, size)
                .dynamicTypeSize(dynamicTypeSize)
        } else {
            self.environment(\.appFontSize, size)
        }
    }

    func appLanguage(_ language: EffectiveAppLanguage) -> some View {
        environment(\.appLanguage, language)
    }
}

struct AppStrings {
    let language: EffectiveAppLanguage

    var brandName: String { language == .chinese ? "简声" : "PureVoice" }
    var libraryTab: String { language == .chinese ? "书架" : "Library" }
    var importTab: String { language == .chinese ? "导入" : "Import" }
    var settingsTab: String { language == .chinese ? "设置" : "Settings" }
    var continueReading: String { language == .chinese ? "继续阅读" : "Continue Reading" }
    var myBooks: String { language == .chinese ? "我的书籍" : "My Books" }
    var reading: String { language == .chinese ? "阅读中" : "Reading" }
    var completed: String { language == .chinese ? "已完成" : "Finished" }
    var rename: String { language == .chinese ? "重命名" : "Rename" }
    var delete: String { language == .chinese ? "删除" : "Delete" }
    var cancel: String { language == .chinese ? "取消" : "Cancel" }
    var save: String { language == .chinese ? "保存" : "Save" }
    var ok: String { language == .chinese ? "好" : "OK" }
    var close: String { language == .chinese ? "关闭" : "Close" }
    var done: String { language == .chinese ? "完成" : "Done" }
    var retry: String { language == .chinese ? "重试" : "Retry" }
    var retrySave: String { language == .chinese ? "重试保存" : "Retry Save" }
    var unknownError: String { language == .chinese ? "发生未知错误" : "An unknown error occurred." }
    var operationFailed: String { language == .chinese ? "操作失败" : "Action Failed" }

    var libraryLoading: String { language == .chinese ? "正在载入书架" : "Loading library" }
    var libraryEmptyTitle: String { language == .chinese ? "书架还是空的" : "Your library is empty" }
    var libraryEmptyHint: String { language == .chinese ? "从“导入”添加本地书籍" : "Use Import to add books from this device." }
    var refreshWebTransfers: String { language == .chinese ? "刷新接收网站传书" : "Refresh Web Transfers" }
    var refreshWebTransfersHint: String { language == .chinese ? "检查网页上传的书籍并导入到书架" : "Check for books uploaded from the website and add them to your library." }
    var refreshLibraryAccessibility: String { language == .chinese ? "刷新书架并接收网站传书" : "Refresh library and receive web transfers" }
    var onlyBookInContinue: String { language == .chinese ? "当前只有一本书，已放在继续阅读中。" : "There is only one book, shown in Continue Reading." }
    var doubleTapContinueHint: String { language == .chinese ? "双击继续阅读。可使用辅助功能操作重命名或删除。" : "Double tap to continue reading. Use accessibility actions to rename or delete." }

    var renameBookTitle: String { language == .chinese ? "重命名" : "Rename Book" }
    var bookNamePlaceholder: String { language == .chinese ? "书名" : "Book Title" }
    func renameBookMessage(_ title: String) -> String {
        language == .chinese ? "为《\(title)》输入新书名" : "Enter a new title for \(title)."
    }
    var deleteBookTitle: String { language == .chinese ? "删除这本书？" : "Delete this book?" }
    func deleteBookMessage(_ title: String) -> String {
        language == .chinese ? "《\(title)》将从书架移除，此操作无法撤销。" : "\(title) will be removed from your library. This cannot be undone."
    }

    var importTitle: String { language == .chinese ? "导入书籍" : "Import Books" }
    var localImportHeading: String { language == .chinese ? "选择本地书籍开始导入" : "Choose a local book to import" }
    var chooseFromDevice: String { language == .chinese ? "从本机选择" : "Choose from This Device" }
    var chooseBookAccessibility: String { language == .chinese ? "选择要导入的书籍文件" : "Choose a book file to import" }
    var supportedImportHint: String { language == .chinese ? "支持 TXT 和 EPUB" : "Supports TXT and EPUB" }
    var importCompleted: String { language == .chinese ? "导入完成" : "Import Complete" }
    var retryPreviousImportHint: String { language == .chinese ? "重新导入上次选择的文件" : "Retry importing the last selected file." }
    var copyingFile: String { language == .chinese ? "正在复制文件" : "Copying file" }
    var detectingFormat: String { language == .chinese ? "正在识别格式" : "Detecting format" }
    var convertingBook: String { language == .chinese ? "正在转换书籍" : "Converting book" }
    var validatingBook: String { language == .chinese ? "正在验证书籍" : "Validating book" }
    var importUnavailable: String { language == .chinese ? "导入功能暂不可用" : "Import is currently unavailable" }

    var webTransferTitle: String { language == .chinese ? "网站传书" : "Web Transfer" }
    var webTransferSubtitle: String { language == .chinese ? "通过线上网址，传入书籍" : "Send books from the web." }
    var transferCode: String { language == .chinese ? "传书码" : "Transfer Code" }
    var transferURL: String { language == .chinese ? "传书网址" : "Transfer Website" }
    var generatingTransferCode: String { language == .chinese ? "正在生成传书码" : "Generating transfer code" }
    var copyTransferCode: String { language == .chinese ? "复制传书码" : "Copy transfer code" }
    var copyTransferURL: String { language == .chinese ? "复制传书网址" : "Copy transfer website" }
    var transferCodeCopied: String { language == .chinese ? "传书码已复制" : "Transfer code copied" }
    var transferURLCopied: String { language == .chinese ? "传书网址已复制" : "Transfer website copied" }
    var copyTransferHint: String { language == .chinese ? "复制后可以发给家人在网站中输入" : "Share it with family so they can upload books on the website." }
    var noPendingFiles: String { language == .chinese ? "暂无待接收文件" : "No pending files" }
    var importAction: String { language == .chinese ? "导入" : "Import" }
    var webTransferAlertTitle: String { language == .chinese ? "网站传书提示" : "Web Transfer Notice" }
    var importItemHint: String { language == .chinese ? "点按导入到书架，长按可删除" : "Tap Import to add it to your library. Long press to delete." }

    var displaySection: String { language == .chinese ? "显示" : "Display" }
    var appLanguage: String { language == .chinese ? "应用语言" : "App Language" }
    var appFontSize: String { language == .chinese ? "应用字体大小" : "App Font Size" }
    var useGlobalSettings: String { language == .chinese ? "使用全局设置" : "Use Global Settings" }
    var readingSection: String { language == .chinese ? "阅读" : "Reading" }
    var fontFamily: String { language == .chinese ? "字体" : "Font" }
    var fontSize: String { language == .chinese ? "字号" : "Text Size" }
    var lineHeight: String { language == .chinese ? "行距" : "Line Spacing" }
    var theme: String { language == .chinese ? "主题" : "Theme" }
    var readerMode: String { language == .chinese ? "阅读模式" : "Reading Mode" }
    var listeningSection: String { language == .chinese ? "听书" : "Listen" }
    var defaultVoice: String { language == .chinese ? "默认声音" : "Default Voice" }
    var systemDefault: String { language == .chinese ? "系统默认" : "System Default" }
    var speechRate: String { language == .chinese ? "语速" : "Speed" }
    var resetDefaults: String { language == .chinese ? "恢复默认设置" : "Reset Defaults" }
    var resetAllDefaultsTitle: String { language == .chinese ? "恢复所有默认设置？" : "Reset all settings?" }
    var resetDefaultConfirm: String { language == .chinese ? "恢复默认" : "Reset" }
    var bookSettingsTitle: String { language == .chinese ? "本书设置" : "Book Settings" }
    var savedVoice: String { language == .chinese ? "已保存的声音" : "Saved Voice" }

    var openingBook: String { language == .chinese ? "正在打开这本书" : "Opening this book" }
    var readerNotice: String { language == .chinese ? "阅读器提示" : "Reader Notice" }
    var readingContent: String { language == .chinese ? "阅读内容" : "Reading Content" }
    var hideReaderControls: String { language == .chinese ? "隐藏阅读控制" : "Hide Reader Controls" }
    var showReaderControls: String { language == .chinese ? "显示阅读控制" : "Show Reader Controls" }
    var tableOfContents: String { language == .chinese ? "目录" : "Table of Contents" }
    var cannotOpenBook: String { language == .chinese ? "无法打开这本书" : "Unable to Open This Book" }
    var backToLibrary: String { language == .chinese ? "返回书架" : "Back to Library" }
    var listen: String { language == .chinese ? "听书" : "Listen" }
    var readerSettings: String { language == .chinese ? "设置" : "Settings" }

    var backToReading: String { language == .chinese ? "返回阅读" : "Back to Reading" }
    var currentSentencePrefix: String { language == .chinese ? "当前句" : "Current sentence" }
    var previousSentence: String { language == .chinese ? "上一句" : "Previous" }
    var play: String { language == .chinese ? "播放" : "Play" }
    var pause: String { language == .chinese ? "暂停" : "Pause" }
    var nextSentence: String { language == .chinese ? "下一句" : "Next" }
    var voice: String { language == .chinese ? "声音" : "Voice" }
    var chooseVoice: String { language == .chinese ? "选择声音" : "Choose Voice" }
    var unavailableVoice: String { language == .chinese ? "无可用声音" : "No Available Voice" }
    var listeningNotice: String { language == .chinese ? "听书提示" : "Listening Notice" }
    var returnToListening: String { language == .chinese ? "返回听书" : "Return to Listening" }
    var closeListening: String { language == .chinese ? "关闭听书" : "Close Listening" }
    var restoreNotice: String { language == .chinese ? "恢复提示" : "Restore Notice" }
    var restoredReadableState: String { language == .chinese ? "已恢复到可继续阅读的状态。" : "Restored to a readable state." }

    func transferCodeAccessibility(_ code: String) -> String {
        language == .chinese ? "传书码 \(code.map(String.init).joined(separator: " "))" : "Transfer code \(code.map(String.init).joined(separator: " "))"
    }

    func transferURLAccessibility(_ url: String) -> String {
        language == .chinese ? "传书网址 \(url)" : "Transfer website \(url)"
    }

    func currentSentenceAccessibility(_ sentence: String) -> String {
        "\(currentSentencePrefix)，\(sentence)"
    }

    func returnToListeningAccessibility(_ title: String) -> String {
        language == .chinese ? "返回听书，\(title)" : "Return to listening, \(title)"
    }

    func bookAccessibilityLabel(for book: Book) -> String {
        let value = Int(((book.position?.progression ?? 0) * 100).rounded())
        if language == .chinese {
            return "\(book.title)，\(book.author)，已读百分之\(Self.chinesePercentage(value))"
        }
        return "\(book.title), \(book.author), \(value) percent read"
    }

    private static func chinesePercentage(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.numberStyle = .spellOut
        return formatter.string(from: NSNumber(value: value))?.replacingOccurrences(of: "〇", with: "零")
            ?? String(value)
    }
}

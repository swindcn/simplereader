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
    static let defaultValue: AppFontSize = .medium
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

    var brandName: String { language == .chinese ? "简声" : "LucidRead" }
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
    var returned: String { language == .chinese ? "已返回" : "Returned" }
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
    var help: String { language == .chinese ? "帮助" : "Help" }
    var helpLibraryAccessibility: String { language == .chinese ? "帮助，查看手势说明" : "Help, view gesture guide" }
    var helpTitle: String { language == .chinese ? "手势帮助" : "Gesture Help" }
    var helpIntro: String {
        language == .chinese
            ? "这些手势主要面向开启旁白后的盲操使用。每次操作都会尽量提供语音与触感反馈。"
            : "These gestures are designed for VoiceOver-first use. Actions provide speech and haptic feedback whenever possible."
    }
    var libraryGesturesSection: String { language == .chinese ? "书架" : "Library" }
    var readerGesturesSection: String { language == .chinese ? "阅读与听书" : "Reading and Listening" }
    var magicTapGesture: String { language == .chinese ? "双指双击" : "Two-finger double tap" }
    var doubleTapGesture: String { language == .chinese ? "单指双击" : "One-finger double tap" }
    var swipeUpDownGesture: String { language == .chinese ? "单指上下滑动" : "One-finger swipe up or down" }
    var threeFingerLeftGesture: String { language == .chinese ? "三指左滑" : "Three-finger swipe left" }
    var threeFingerRightGesture: String { language == .chinese ? "三指右滑" : "Three-finger swipe right" }
    var threeFingerUpDownGesture: String { language == .chinese ? "三指上滑 / 下滑" : "Three-finger swipe up or down" }
    var scrubGesture: String { language == .chinese ? "双指 Z 字划动" : "Two-finger scrub" }
    var libraryMagicTapHelpTitle: String { language == .chinese ? "继续听上一本书" : "Resume the last book" }
    var libraryMagicTapHelpDescription: String {
        language == .chinese
            ? "在书架任意位置双指双击，直接继续播放最近阅读或听书的书籍。"
            : "Double tap with two fingers anywhere on the library to resume the most recent book."
    }
    var bookActivateHelpTitle: String { language == .chinese ? "打开书籍" : "Open a book" }
    var bookActivateHelpDescription: String {
        language == .chinese
            ? "焦点停在书籍卡片上时单指双击，进入阅读页面。"
            : "When a book card is focused, double tap with one finger to open it."
    }
    var bookActionsHelpTitle: String { language == .chinese ? "切换书籍操作" : "Choose book actions" }
    var bookActionsHelpDescription: String {
        language == .chinese
            ? "焦点停在书籍卡片上时单指上下滑动，可在重命名、删除等操作间切换，再双击执行。"
            : "When a book card is focused, swipe up or down with one finger to choose actions such as rename or delete, then double tap."
    }
    var playbackMagicTapHelpTitle: String { language == .chinese ? "播放或暂停" : "Play or pause" }
    var playbackMagicTapHelpDescription: String {
        language == .chinese
            ? "在阅读页或听书页任意位置双指双击，播放或暂停听书。"
            : "Double tap with two fingers anywhere in the reader or listening view to play or pause speech."
    }
    var nextChapterHelpTitle: String { language == .chinese ? "下一章" : "Next chapter" }
    var nextChapterHelpDescription: String {
        language == .chinese
            ? "在阅读页或听书页三指左滑，跳到下一章。"
            : "Swipe left with three fingers in the reader or listening view to move to the next chapter."
    }
    var previousChapterHelpTitle: String { language == .chinese ? "上一章" : "Previous chapter" }
    var previousChapterHelpDescription: String {
        language == .chinese
            ? "在阅读页或听书页三指右滑，跳到上一章。"
            : "Swipe right with three fingers in the reader or listening view to move to the previous chapter."
    }
    var speechRateHelpTitle: String { language == .chinese ? "调整语速" : "Adjust speech speed" }
    var speechRateHelpDescription: String {
        language == .chinese
            ? "在听书页三指上滑提高语速，三指下滑降低语速。"
            : "In the listening view, swipe up with three fingers to speed up, or down to slow down."
    }
    var escapeHelpTitle: String { language == .chinese ? "返回书架" : "Return to library" }
    var escapeHelpDescription: String {
        language == .chinese
            ? "在阅读页或听书页双指画 Z 字，保存进度并返回书架。"
            : "Scrub with two fingers in the reader or listening view to save progress and return to the library."
    }
    var onlyBookInContinue: String { language == .chinese ? "当前只有一本书，已放在继续阅读中。" : "There is only one book, shown in Continue Reading." }
    var doubleTapContinueHint: String { language == .chinese ? "双击继续阅读。可使用辅助功能操作重命名或删除。" : "Double tap to continue reading. Use accessibility actions to rename or delete." }
    func enteredBook(_ title: String) -> String {
        language == .chinese ? "已进入《\(title)》" : "Opened \(title)"
    }
    func continueListeningAnnouncement(_ title: String) -> String {
        language == .chinese ? "继续播放《\(title)》" : "Continuing \(title)"
    }

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
    var supportedImportHint: String { language == .chinese ? "支持 EPUB 和 TXT" : "Supports EPUB and TXT" }
    var importCompleted: String { language == .chinese ? "导入完成" : "Import Complete" }
    var retryPreviousImportHint: String { language == .chinese ? "重新导入上次选择的文件" : "Retry importing the last selected file." }
    var copyingFile: String { language == .chinese ? "正在复制文件" : "Copying file" }
    var detectingFormat: String { language == .chinese ? "正在识别格式" : "Detecting format" }
    var convertingBook: String { language == .chinese ? "正在转换书籍" : "Converting book" }
    var validatingBook: String { language == .chinese ? "正在验证书籍" : "Validating book" }
    var importUnavailable: String { language == .chinese ? "导入功能暂不可用" : "Import is currently unavailable" }

    var webTransferTitle: String { language == .chinese ? "网站传书" : "Web Transfer" }
    var webTransferSubtitle: String { language == .chinese ? "从网站发送书籍" : "Send books from the Web" }
    var transferCode: String { language == .chinese ? "传书码" : "Transfer Code" }
    var transferURL: String { language == .chinese ? "传书网址" : "Transfer Website" }
    var transferCodeInstruction: String { language == .chinese ? "在传书网站输入这个代码" : "Enter this code on the transfer website" }
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
    var appVersion: String { language == .chinese ? "版本号" : "Version" }
    var checkForUpdatesHint: String { language == .chinese ? "打开 App Store 检测是否有新版本" : "Open the App Store to check for updates." }
    func appVersionDisplay(_ version: String) -> String {
        language == .chinese ? "版本 \(version)" : "Version \(version)"
    }
    var subscription: String { language == .chinese ? "订阅" : "Subscription" }
    var notSubscribed: String { language == .chinese ? "未订阅" : "Not Subscribed" }
    var monthlySubscription: String { language == .chinese ? "月订阅" : "Monthly" }
    var annualSubscription: String { language == .chinese ? "年订阅" : "Annual" }
    var lifetimeSubscription: String { language == .chinese ? "永久买断" : "Lifetime" }
    var activeSubscription: String { language == .chinese ? "已订阅" : "Subscribed" }
    func subscriptionExpires(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return language == .chinese
            ? "到期 \(formatter.string(from: date))"
            : "Expires \(formatter.string(from: date))"
    }

    var openingBook: String { language == .chinese ? "正在打开这本书" : "Opening this book" }
    var readerNotice: String { language == .chinese ? "阅读器提示" : "Reader Notice" }
    var readingContent: String { language == .chinese ? "阅读内容" : "Reading Content" }
    var hideReaderControls: String { language == .chinese ? "隐藏阅读控制" : "Hide Reader Controls" }
    var showReaderControls: String { language == .chinese ? "显示阅读控制" : "Show Reader Controls" }
    var savedAndReturnedToLibrary: String { language == .chinese ? "已保存进度，已返回书架" : "Progress saved. Returned to library." }
    func nextChapterAnnouncement(_ title: String) -> String {
        language == .chinese ? "下一章，\(title)" : "Next chapter, \(title)"
    }
    func previousChapterAnnouncement(_ title: String) -> String {
        language == .chinese ? "上一章，\(title)" : "Previous chapter, \(title)"
    }
    var tableOfContents: String { language == .chinese ? "目录" : "Table of Contents" }
    var cannotOpenBook: String { language == .chinese ? "无法打开这本书" : "Unable to Open This Book" }
    var backToLibrary: String { language == .chinese ? "返回书架" : "Back to Library" }
    var listen: String { language == .chinese ? "听书" : "Listen" }
    var readerSettings: String { language == .chinese ? "设置" : "Settings" }

    var backToReading: String { language == .chinese ? "返回阅读" : "Back to Reading" }
    var currentSentencePrefix: String { language == .chinese ? "当前句" : "Current sentence" }
    var previousSentence: String { language == .chinese ? "上一句" : "Previous" }
    var previousChapterControl: String { language == .chinese ? "上一章" : "Previous Chapter" }
    var play: String { language == .chinese ? "播放" : "Play" }
    var pause: String { language == .chinese ? "暂停" : "Pause" }
    var nextSentence: String { language == .chinese ? "下一句" : "Next" }
    var nextChapterControl: String { language == .chinese ? "下一章" : "Next Chapter" }
    var voice: String { language == .chinese ? "声音" : "Voice" }
    var chooseVoice: String { language == .chinese ? "选择声音" : "Choose Voice" }
    var unavailableVoice: String { language == .chinese ? "无可用声音" : "No Available Voice" }
    var listeningNotice: String { language == .chinese ? "听书提示" : "Listening Notice" }
    var returnToListening: String { language == .chinese ? "返回听书" : "Return to Listening" }
    var closeListening: String { language == .chinese ? "关闭听书" : "Close Listening" }
    var restoreNotice: String { language == .chinese ? "恢复提示" : "Restore Notice" }
    var restoredReadableState: String { language == .chinese ? "已恢复到可继续阅读的状态。" : "Restored to a readable state." }

    var purchaseNotice: String { language == .chinese ? "购买提示" : "Purchase Notice" }
    var closePaywall: String { language == .chinese ? "关闭付费页面" : "Close paywall" }
    var paywallTitle: String { language == .chinese ? "解锁无限阅读" : "Unlock Unlimited Reading" }
    var paywallSubtitle: String {
        language == .chinese
            ? "无广告，纯净阅读体验，为轻松的旁白导航而设计。"
            : "Ad-free, pure reading experience designed for effortless VoiceOver navigation."
    }
    var monthlyPro: String { language == .chinese ? "月度 Pro" : "Monthly Pro" }
    var annualPro: String { language == .chinese ? "年度 Pro" : "Annual Pro" }
    var lifetimeAccess: String { language == .chinese ? "永久买断" : "Lifetime Access" }
    var monthlyProDetail: String { language == .chinese ? "按月订阅，随时可在 App Store 设置中取消。" : "Monthly subscription, cancel anytime in App Store Settings." }
    var annualProDetail: String { language == .chinese ? "更划算的年度方案，试用结束后按年扣费。" : "Best value, billed annually after trial." }
    var lifetimeAccessDetail: String { language == .chinese ? "一次付费，永久阅读与后续更新。" : "One-time payment, lifetime updates." }
    var perMonth: String { language == .chinese ? "/ 月" : "/ month" }
    var perYear: String { language == .chinese ? "/ 年" : "/ year" }
    var includesSevenDayTrial: String { language == .chinese ? "包含 7 天免费试用" : "Includes 7-Day Free Trial" }
    var bestValue: String { language == .chinese ? "最划算" : "Best Value" }
    var startSevenDayTrial: String { language == .chinese ? "开始 7 天免费试用" : "Start 7-Day Free Trial" }
    var continuePurchase: String { language == .chinese ? "继续购买" : "Continue" }
    var cancelInAppStoreSettings: String {
        language == .chinese
            ? "可在 App Store 设置中随时取消订阅，请至少在试用结束前 24 小时取消。"
            : "Cancel anytime in App Store Settings at least 24 hours before trial ends."
    }
    var restorePurchases: String { language == .chinese ? "恢复购买" : "Restore Purchases" }
    var privacyPolicy: String { language == .chinese ? "隐私政策" : "Privacy Policy" }
    var termsOfService: String { language == .chinese ? "服务条款" : "Terms of Service" }
    var paywallCopyright: String { "© 2026 LucidRead by WildGrassX. All rights reserved." }
    func freeTrialRemaining(_ days: Int) -> String {
        language == .chinese ? "新设备免费期剩余 \(days) 天" : "\(days) days left in your free device trial"
    }

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

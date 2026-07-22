import Foundation
import UIKit

enum AppFontSize: String, Codable, CaseIterable, Sendable {
    case small
    case medium
    case large
    case extraLarge

    var title: String {
        switch self {
        case .small: "小"
        case .medium: "中"
        case .large: "大"
        case .extraLarge: "极大"
        }
    }
}

enum ReaderFontFamily: String, Codable, CaseIterable, Sendable {
    case system
    case serif
    case sans

    var title: String {
        switch self {
        case .system: "系统字体"
        case .serif: "衬线字体"
        case .sans: "无衬线字体"
        }
    }
}

enum ReaderTheme: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case sepia
    case dark

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .sepia: "护眼"
        case .dark: "深色"
        }
    }

    func readerAppearance(usesDarkSystemTheme: Bool) -> ReaderThemeAppearance {
        switch self {
        case .system:
            return usesDarkSystemTheme ? .dark : .light
        case .light:
            return .light
        case .sepia:
            return .sepia
        case .dark:
            return .dark
        }
    }
}

struct ReaderThemeAppearance: Equatable, Sendable {
    let backgroundColor: UIColor
    let chromeBackgroundColor: UIColor
}

extension ReaderThemeAppearance {
    static let light = ReaderThemeAppearance(
        backgroundColor: .white,
        chromeBackgroundColor: .pureVoiceLightChrome
    )

    static let sepia = ReaderThemeAppearance(
        backgroundColor: .pureVoiceSepiaBackground,
        chromeBackgroundColor: .pureVoiceSepiaChrome
    )

    static let dark = ReaderThemeAppearance(
        backgroundColor: .black,
        chromeBackgroundColor: .pureVoiceDarkChrome
    )
}

extension UIColor {
    static let pureVoiceLightChrome = UIColor(red: 0.96, green: 0.96, blue: 0.95, alpha: 1)
    static let pureVoiceSepiaBackground = UIColor(red: 0.98, green: 0.94, blue: 0.86, alpha: 1)
    static let pureVoiceSepiaChrome = UIColor(red: 0.93, green: 0.86, blue: 0.73, alpha: 1)
    static let pureVoiceDarkChrome = UIColor(red: 0.03, green: 0.03, blue: 0.03, alpha: 1)
}

enum ReaderLayout: String, Codable, CaseIterable, Sendable {
    case paginated
    case scroll

    var title: String {
        switch self {
        case .paginated: "左右分页"
        case .scroll: "上下滚动"
        }
    }
}

enum ReaderDynamicTypeCategory: Sendable {
    case extraSmall
    case small
    case medium
    case large
    case extraLarge
    case extraExtraLarge
    case extraExtraExtraLarge
    case accessibilityMedium
    case accessibilityLarge
    case accessibilityExtraLarge
    case accessibilityExtraExtraLarge
    case accessibilityExtraExtraExtraLarge

    var multiplier: Double {
        switch self {
        case .extraSmall: 0.82
        case .small: 0.88
        case .medium: 0.94
        case .large: 1
        case .extraLarge: 1.12
        case .extraExtraLarge: 1.24
        case .extraExtraExtraLarge: 1.35
        case .accessibilityMedium: 1.5
        case .accessibilityLarge: 1.65
        case .accessibilityExtraLarge: 1.8
        case .accessibilityExtraExtraLarge: 1.9
        case .accessibilityExtraExtraExtraLarge: 2
        }
    }
}

struct ReaderPreferences: Codable, Equatable, Sendable {
    static let defaults = ReaderPreferences()

    var fontFamily: ReaderFontFamily
    var fontScale: Double
    var lineHeight: Double
    var theme: ReaderTheme
    var layout: ReaderLayout
    var appFontSize: AppFontSize
    var voiceIdentifier: String?
    var speechRate: Double

    init(
        fontFamily: ReaderFontFamily = .system,
        fontScale: Double = 1,
        lineHeight: Double = 1.5,
        theme: ReaderTheme = .sepia,
        layout: ReaderLayout = .paginated,
        appFontSize: AppFontSize = .extraLarge,
        voiceIdentifier: String? = nil,
        speechRate: Double = 1
    ) {
        self.fontFamily = fontFamily
        self.fontScale = fontScale
        self.lineHeight = lineHeight
        self.theme = theme
        self.layout = layout
        self.appFontSize = appFontSize
        self.voiceIdentifier = voiceIdentifier
        self.speechRate = speechRate
    }

    enum CodingKeys: String, CodingKey {
        case fontFamily
        case fontScale
        case lineHeight
        case theme
        case layout
        case appFontSize
        case voiceIdentifier
        case speechRate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            fontFamily: try container.decode(ReaderFontFamily.self, forKey: .fontFamily),
            fontScale: try container.decode(Double.self, forKey: .fontScale),
            lineHeight: try container.decode(Double.self, forKey: .lineHeight),
            theme: try container.decode(ReaderTheme.self, forKey: .theme),
            layout: try container.decode(ReaderLayout.self, forKey: .layout),
            appFontSize: try container.decodeIfPresent(AppFontSize.self, forKey: .appFontSize) ?? .extraLarge,
            voiceIdentifier: try container.decodeIfPresent(String.self, forKey: .voiceIdentifier),
            speechRate: try container.decode(Double.self, forKey: .speechRate)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fontFamily, forKey: .fontFamily)
        try container.encode(fontScale, forKey: .fontScale)
        try container.encode(lineHeight, forKey: .lineHeight)
        try container.encode(theme, forKey: .theme)
        try container.encode(layout, forKey: .layout)
        try container.encode(appFontSize, forKey: .appFontSize)
        try container.encodeIfPresent(voiceIdentifier, forKey: .voiceIdentifier)
        try container.encode(speechRate, forKey: .speechRate)
    }

    func effectiveFontScale(for category: ReaderDynamicTypeCategory) -> Double {
        min(fontScale * category.multiplier, 3)
    }

    func sanitized() -> ReaderPreferences {
        var copy = self
        copy.fontScale = Self.validated(fontScale, fallback: 1, range: 0.8 ... 2)
        copy.lineHeight = Self.validated(lineHeight, fallback: 1.5, range: 1 ... 2.2)
        copy.speechRate = Self.validated(speechRate, fallback: 1, range: 0.5 ... 2)
        if copy.voiceIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            copy.voiceIdentifier = nil
        }
        return copy
    }

    private static func validated(_ value: Double, fallback: Double, range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

struct ReaderPreferencesOverride: Codable, Equatable, Sendable {
    enum Voice: Codable, Equatable, Sendable {
        case systemDefault
        case identifier(String)
    }

    var fontFamily: ReaderFontFamily?
    var fontScale: Double?
    var lineHeight: Double?
    var theme: ReaderTheme?
    var layout: ReaderLayout?
    var voice: Voice?
    var speechRate: Double?

    init(
        fontFamily: ReaderFontFamily? = nil,
        fontScale: Double? = nil,
        lineHeight: Double? = nil,
        theme: ReaderTheme? = nil,
        layout: ReaderLayout? = nil,
        voice: Voice? = nil,
        speechRate: Double? = nil
    ) {
        self.fontFamily = fontFamily
        self.fontScale = fontScale
        self.lineHeight = lineHeight
        self.theme = theme
        self.layout = layout
        self.voice = voice
        self.speechRate = speechRate
    }

    func resolving(_ global: ReaderPreferences) -> ReaderPreferences {
        ReaderPreferences(
            fontFamily: fontFamily ?? global.fontFamily,
            fontScale: fontScale ?? global.fontScale,
            lineHeight: lineHeight ?? global.lineHeight,
            theme: theme ?? global.theme,
            layout: layout ?? global.layout,
            appFontSize: global.appFontSize,
            voiceIdentifier: resolvedVoiceIdentifier(inheriting: global.voiceIdentifier),
            speechRate: speechRate ?? global.speechRate
        ).sanitized()
    }

    static func freezing(_ preferences: ReaderPreferences) -> ReaderPreferencesOverride {
        ReaderPreferencesOverride(
            fontFamily: preferences.fontFamily,
            fontScale: preferences.fontScale,
            lineHeight: preferences.lineHeight,
            theme: preferences.theme,
            layout: preferences.layout,
            voice: preferences.voiceIdentifier.map(Voice.identifier) ?? .systemDefault,
            speechRate: preferences.speechRate
        )
    }

    func sanitized() -> ReaderPreferencesOverride {
        let resolved = resolving(.defaults)
        return ReaderPreferencesOverride(
            fontFamily: fontFamily,
            fontScale: fontScale == nil ? nil : resolved.fontScale,
            lineHeight: lineHeight == nil ? nil : resolved.lineHeight,
            theme: theme,
            layout: layout,
            voice: voice,
            speechRate: speechRate == nil ? nil : resolved.speechRate
        )
    }

    private func resolvedVoiceIdentifier(inheriting global: String?) -> String? {
        switch voice {
        case .none:
            global
        case .systemDefault:
            nil
        case let .identifier(identifier):
            identifier
        }
    }
}

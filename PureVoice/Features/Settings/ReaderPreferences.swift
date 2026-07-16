import Foundation

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
}

enum ReaderLayout: String, Codable, CaseIterable, Sendable {
    case paginated
    case scroll

    var title: String {
        switch self {
        case .paginated: "分页"
        case .scroll: "滚动"
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
    var voiceIdentifier: String?
    var speechRate: Double

    init(
        fontFamily: ReaderFontFamily = .system,
        fontScale: Double = 1,
        lineHeight: Double = 1.5,
        theme: ReaderTheme = .system,
        layout: ReaderLayout = .paginated,
        voiceIdentifier: String? = nil,
        speechRate: Double = 1
    ) {
        self.fontFamily = fontFamily
        self.fontScale = fontScale
        self.lineHeight = lineHeight
        self.theme = theme
        self.layout = layout
        self.voiceIdentifier = voiceIdentifier
        self.speechRate = speechRate
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
    var fontFamily: ReaderFontFamily?
    var fontScale: Double?
    var lineHeight: Double?
    var theme: ReaderTheme?
    var layout: ReaderLayout?

    init(
        fontFamily: ReaderFontFamily? = nil,
        fontScale: Double? = nil,
        lineHeight: Double? = nil,
        theme: ReaderTheme? = nil,
        layout: ReaderLayout? = nil
    ) {
        self.fontFamily = fontFamily
        self.fontScale = fontScale
        self.lineHeight = lineHeight
        self.theme = theme
        self.layout = layout
    }

    func resolving(_ global: ReaderPreferences) -> ReaderPreferences {
        ReaderPreferences(
            fontFamily: fontFamily ?? global.fontFamily,
            fontScale: fontScale ?? global.fontScale,
            lineHeight: lineHeight ?? global.lineHeight,
            theme: theme ?? global.theme,
            layout: layout ?? global.layout,
            voiceIdentifier: global.voiceIdentifier,
            speechRate: global.speechRate
        ).sanitized()
    }

    func sanitized() -> ReaderPreferencesOverride {
        let resolved = resolving(.defaults)
        return ReaderPreferencesOverride(
            fontFamily: fontFamily,
            fontScale: fontScale == nil ? nil : resolved.fontScale,
            lineHeight: lineHeight == nil ? nil : resolved.lineHeight,
            theme: theme,
            layout: layout
        )
    }
}

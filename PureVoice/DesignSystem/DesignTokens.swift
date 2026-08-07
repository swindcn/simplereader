import CoreHaptics
import SwiftUI
import UIKit

enum DesignTokens {
    static let minimumTouchTarget: CGFloat = 60
    static let cardRadius: CGFloat = 8
    static let edgeMargin: CGFloat = 24
    static let stackGap: CGFloat = 16

    static let primary = Color(uiColor: .pureVoicePrimary)
    static let background = Color(uiColor: .pureVoiceAppBackground)
    static let surface = Color(uiColor: .pureVoiceAppSurface)
    static let surfaceElevated = Color(uiColor: .pureVoiceAppSurfaceElevated)
    static let fieldBackground = Color(uiColor: .pureVoiceFieldBackground)
    static let onSurface = Color(uiColor: .pureVoiceOnSurface)
    static let onSurfaceVariant = Color(uiColor: .pureVoiceOnSurfaceVariant)
    static let outline = Color(uiColor: .pureVoiceOutline)
}

extension UIColor {
    static let pureVoicePrimary = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.654, green: 0.545, blue: 0.980, alpha: 1)
            : UIColor(red: 0, green: 65 / 255, blue: 200 / 255, alpha: 1)
    }

    static let pureVoiceAppBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.078, green: 0.071, blue: 0.098, alpha: 1)
            : UIColor.systemGroupedBackground
    }

    static let pureVoiceAppSurface = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.114, green: 0.102, blue: 0.129, alpha: 1)
            : UIColor(red: 250 / 255, green: 248 / 255, blue: 1, alpha: 1)
    }

    static let pureVoiceAppSurfaceElevated = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.129, green: 0.118, blue: 0.145, alpha: 1)
            : UIColor.systemBackground
    }

    static let pureVoiceFieldBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.169, green: 0.161, blue: 0.188, alpha: 1)
            : UIColor(red: 0.937, green: 0.937, blue: 0.937, alpha: 1)
    }

    static let pureVoiceOnSurface = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.902, green: 0.878, blue: 0.918, alpha: 1)
            : UIColor(red: 25 / 255, green: 27 / 255, blue: 37 / 255, alpha: 1)
    }

    static let pureVoiceOnSurfaceVariant = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.792, green: 0.769, blue: 0.831, alpha: 1)
            : UIColor.secondaryLabel
    }

    static let pureVoiceOutline = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.286, green: 0.271, blue: 0.322, alpha: 1)
            : UIColor.separator
    }
}

extension View {
    @ViewBuilder
    func hidingScrollContentBackgroundIfAvailable() -> some View {
        if #available(iOS 16.0, *) {
            scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}

enum AccessibilityFeedback {
    @MainActor
    private static var hapticEngine: CHHapticEngine?

    @MainActor
    static func announce(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    @MainActor
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        if playCoreHaptic(for: style) { return }
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    @MainActor
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        if playCoreHaptic(for: type) { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    @MainActor
    static func doubleLightPulse() {
        impact(.light)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            impact(.light)
        }
    }

    @MainActor
    private static func playCoreHaptic(for style: UIImpactFeedbackGenerator.FeedbackStyle) -> Bool {
        switch style {
        case .light:
            return playCoreHaptic(intensity: 0.32, sharpness: 0.55)
        case .medium:
            return playCoreHaptic(intensity: 0.58, sharpness: 0.55)
        case .heavy:
            return playCoreHaptic(intensity: 0.86, sharpness: 0.75)
        case .soft:
            return playCoreHaptic(intensity: 0.42, sharpness: 0.25)
        case .rigid:
            return playCoreHaptic(intensity: 0.68, sharpness: 0.95)
        @unknown default:
            return playCoreHaptic(intensity: 0.5, sharpness: 0.5)
        }
    }

    @MainActor
    private static func playCoreHaptic(for type: UINotificationFeedbackGenerator.FeedbackType) -> Bool {
        switch type {
        case .success:
            return playCoreHaptic(intensity: 0.52, sharpness: 0.45)
        case .warning:
            return playCoreHaptic(intensity: 0.75, sharpness: 0.85)
        case .error:
            return playCoreHaptic(intensity: 0.9, sharpness: 0.95)
        @unknown default:
            return playCoreHaptic(intensity: 0.6, sharpness: 0.6)
        }
    }

    @MainActor
    private static func playCoreHaptic(intensity: Float, sharpness: Float) -> Bool {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return false }
        do {
            if hapticEngine == nil {
                hapticEngine = try CHHapticEngine()
                hapticEngine?.resetHandler = {
                    Task { @MainActor in
                        try? hapticEngine?.start()
                    }
                }
            }
            try hapticEngine?.start()
            let event = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                ],
                relativeTime: 0
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try hapticEngine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
            return true
        } catch {
            hapticEngine = nil
            return false
        }
    }
}

import Foundation

enum LegalDocument: CaseIterable {
    case terms
    case privacy

    var url: URL {
        switch self {
        case .terms:
            URL(string: "https://www.wildgrassx.com/terms")!
        case .privacy:
            URL(string: "https://www.wildgrassx.com/privacy")!
        }
    }

    var identifier: String {
        switch self {
        case .terms:
            "terms"
        case .privacy:
            "privacy"
        }
    }

    func title(in strings: AppStrings) -> String {
        switch self {
        case .terms:
            strings.termsOfService
        case .privacy:
            strings.privacyPolicy
        }
    }
}

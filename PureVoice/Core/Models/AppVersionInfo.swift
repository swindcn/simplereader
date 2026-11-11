import Foundation

struct AppVersionInfo: Equatable {
    static let appStoreID = "6793768789"

    let shortVersion: String
    let buildNumber: String

    var updateURL: URL {
        URL(string: "itms-apps://apps.apple.com/app/id\(Self.appStoreID)")!
    }

    static func current(bundle: Bundle = .main) -> AppVersionInfo {
        AppVersionInfo(
            shortVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0",
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        )
    }

    func displayText(in strings: AppStrings) -> String {
        strings.appVersionDisplay(shortVersion)
    }
}

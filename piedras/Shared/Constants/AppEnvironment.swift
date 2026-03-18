import Foundation

enum AppEnvironment {
    nonisolated(unsafe) static let cloudName = "Piedras Cloud"
    nonisolated(unsafe) static let productionBackendBaseURLString = "https://piedras-api.vercel.app"
    nonisolated(unsafe) static let productionBackendBaseURL = URL(string: productionBackendBaseURLString)!

    static var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        switch (version, build) {
        case let (.some(version), .some(build)):
            return "\(version) (\(build))"
        case let (.some(version), .none):
            return version
        case let (.none, .some(build)):
            return build
        default:
            return "1.0"
        }
    }
}

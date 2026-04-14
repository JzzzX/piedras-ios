import Foundation

enum AppEnvironment {
    private enum Key {
        static let backendBaseURL = "COCO_INTERVIEW_BACKEND_BASE_URL"
    }

    private nonisolated static let defaultProductionBackendBaseURLString = "https://cocotranslate.com"

    nonisolated static let cloudName = "椰子面试 Cloud"

    static var productionBackendBaseURLString: String {
        configuredProductionBackendBaseURL?.absoluteString ?? defaultProductionBackendBaseURLString
    }

    static var productionBackendBaseURL: URL {
        configuredProductionBackendBaseURL ?? URL(string: defaultProductionBackendBaseURLString)!
    }

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

    private static var configuredProductionBackendBaseURL: URL? {
        let configuredValue = ProcessInfo.processInfo.environment[Key.backendBaseURL]
            ?? (Bundle.main.object(forInfoDictionaryKey: Key.backendBaseURL) as? String)

        guard let configuredValue else {
            return nil
        }

        let normalized = configuredValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }

        return URL(string: normalized)
    }
}

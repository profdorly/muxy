import Foundation

enum FeatureFlag: String, CaseIterable, Sendable {
    case updateAvailableSimulation = "muxy.feature.updateAvailableSimulation"

    var defaultValue: Bool {
        switch self {
        case .updateAvailableSimulation: false
        }
    }

    var environmentVariable: String {
        switch self {
        case .updateAvailableSimulation: "FF_UPDATE_AVAILABLE"
        }
    }

    var displayName: String {
        switch self {
        case .updateAvailableSimulation: "Simulate Available Update"
        }
    }
}

@MainActor @Observable
final class FeatureFlagService {
    static let shared = FeatureFlagService()

    private static let overridePrefix = "muxy.feature.override."

    private let defaults: UserDefaults
    private let environment: [String: String]

    init(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.defaults = defaults
        self.environment = environment
    }

    func isEnabled(_ flag: FeatureFlag) -> Bool {
        #if DEBUG
        if let raw = environment[flag.environmentVariable] {
            return Self.truthy(raw)
        }
        #endif
        if let override = overrideValue(for: flag) {
            return override
        }
        return flag.defaultValue
    }

    func overrideValue(for flag: FeatureFlag) -> Bool? {
        defaults.object(forKey: Self.overrideKey(for: flag)) as? Bool
    }

    func setOverride(_ flag: FeatureFlag, _ value: Bool?) {
        let key = Self.overrideKey(for: flag)
        guard let value else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(value, forKey: key)
    }

    func resetOverrides() {
        for flag in FeatureFlag.allCases {
            defaults.removeObject(forKey: Self.overrideKey(for: flag))
        }
    }

    private static func overrideKey(for flag: FeatureFlag) -> String {
        overridePrefix + flag.rawValue
    }

    private static func truthy(_ raw: String) -> Bool {
        switch raw.lowercased() {
        case "1",
             "true",
             "yes",
             "on": true
        default: false
        }
    }
}

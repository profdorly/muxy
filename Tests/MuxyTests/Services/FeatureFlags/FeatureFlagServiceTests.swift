import Foundation
import Testing

@testable import Muxy

@Suite("Feature flag service")
struct FeatureFlagServiceTests {
    @MainActor
    private func makeService(
        defaults: UserDefaults,
        environment: [String: String] = [:]
    ) -> FeatureFlagService {
        FeatureFlagService(defaults: defaults, environment: environment)
    }

    @Test("flags fall back to their default value")
    @MainActor
    func flagsFallBackToDefault() throws {
        let suiteName = "FeatureFlagServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = makeService(defaults: defaults)
        for flag in FeatureFlag.allCases {
            #expect(service.isEnabled(flag) == flag.defaultValue)
        }
    }

    @Test("user defaults override wins over the default and persists")
    @MainActor
    func overrideWinsAndPersists() throws {
        let suiteName = "FeatureFlagServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = makeService(defaults: defaults)
        service.setOverride(.updateAvailableSimulation, true)
        #expect(service.isEnabled(.updateAvailableSimulation))
        #expect(service.overrideValue(for: .updateAvailableSimulation) == true)

        let reloaded = makeService(defaults: defaults)
        #expect(reloaded.isEnabled(.updateAvailableSimulation))
    }

    @Test("clearing an override restores the default")
    @MainActor
    func clearingOverrideRestoresDefault() throws {
        let suiteName = "FeatureFlagServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = makeService(defaults: defaults)
        service.setOverride(.updateAvailableSimulation, true)
        service.setOverride(.updateAvailableSimulation, nil)
        #expect(service.overrideValue(for: .updateAvailableSimulation) == nil)
        #expect(service.isEnabled(.updateAvailableSimulation) == false)
    }

    @Test("resetOverrides clears every flag")
    @MainActor
    func resetOverridesClearsEverything() throws {
        let suiteName = "FeatureFlagServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = makeService(defaults: defaults)
        for flag in FeatureFlag.allCases {
            service.setOverride(flag, true)
        }
        service.resetOverrides()
        for flag in FeatureFlag.allCases {
            #expect(service.overrideValue(for: flag) == nil)
        }
    }

    #if DEBUG
    @Test("environment variable wins in debug builds")
    @MainActor
    func environmentWinsInDebug() throws {
        let suiteName = "FeatureFlagServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = makeService(
            defaults: defaults,
            environment: ["FF_UPDATE_AVAILABLE": "1"]
        )
        #expect(service.isEnabled(.updateAvailableSimulation))

        let disabled = makeService(
            defaults: defaults,
            environment: ["FF_UPDATE_AVAILABLE": "0"]
        )
        #expect(!disabled.isEnabled(.updateAvailableSimulation))
    }
    #endif

    @Test("flag metadata is stable")
    func flagMetadataIsStable() {
        #expect(FeatureFlag.updateAvailableSimulation.environmentVariable == "FF_UPDATE_AVAILABLE")
        #expect(FeatureFlag.updateAvailableSimulation.defaultValue == false)
        #expect(!FeatureFlag.updateAvailableSimulation.displayName.isEmpty)
    }
}

import Foundation
import Testing

@testable import Muxy

@Suite("AnalyticsService")
@MainActor
struct AnalyticsServiceTests {
    @Test("needsPrompt is true when API key is present and consent is undecided")
    func needsPromptWhenKeyAndUndecided() {
        let (service, _, suiteName) = makeService(apiKey: "phc_test")
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        #expect(service.hasAPIKey)
        #expect(service.consent == nil)
        #expect(service.needsPrompt)
    }

    @Test("needsPrompt is false when API key is missing")
    func needsPromptFalseWithoutKey() {
        let (service, _, suiteName) = makeService(apiKey: nil)
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        #expect(!service.hasAPIKey)
        #expect(!service.needsPrompt)
    }

    @Test("setConsent persists denied and reports needsPrompt false")
    func setConsentDeniedPersists() {
        let (service, defaults, suiteName) = makeService(apiKey: "phc_test")
        defer { defaults.removePersistentDomain(forName: suiteName) }

        service.setConsent(.denied)

        #expect(service.consent == .denied)
        #expect(!service.needsPrompt)
        #expect(defaults.string(forKey: AnalyticsConsent.storageKey) == "denied")
    }

    @Test("setConsent allowed starts the SDK; denied stops it")
    func setConsentTogglesStartAndStop() {
        var startCount = 0
        var stopCount = 0
        let (service, defaults, suiteName) = makeService(
            apiKey: "phc_test",
            starter: { _ in startCount += 1 },
            stopper: { stopCount += 1 }
        )
        defer { defaults.removePersistentDomain(forName: suiteName) }

        service.setConsent(.allowed)
        #expect(startCount == 1)
        #expect(stopCount == 0)

        service.setConsent(.allowed)
        #expect(startCount == 1, "start must be idempotent")

        service.setConsent(.denied)
        #expect(stopCount == 1)

        service.setConsent(.denied)
        #expect(stopCount == 1, "stop must be idempotent")
    }

    @Test("start is a no-op when API key is missing even with allowed consent")
    func startNoOpWithoutKey() {
        var startCount = 0
        let (service, defaults, suiteName) = makeService(
            apiKey: nil,
            starter: { _ in startCount += 1 }
        )
        defer { defaults.removePersistentDomain(forName: suiteName) }

        service.setConsent(.allowed)

        #expect(startCount == 0)
    }

    @Test("capture only forwards events while consented and started")
    func captureRespectsConsent() {
        var captured: [String] = []
        let (service, defaults, suiteName) = makeService(
            apiKey: "phc_test",
            capturer: { event, _ in captured.append(event) }
        )
        defer { defaults.removePersistentDomain(forName: suiteName) }

        service.capture(.extensionInstalled)
        #expect(captured.isEmpty, "capture must be a no-op before consent")

        service.setConsent(.allowed)
        #expect(captured == [AnalyticsEvent.appLaunched.rawValue], "start emits app_launched")

        service.capture(.extensionInstalled)
        #expect(captured == [
            AnalyticsEvent.appLaunched.rawValue,
            AnalyticsEvent.extensionInstalled.rawValue,
        ])

        service.setConsent(.denied)
        service.capture(.extensionInstalled)
        #expect(captured.count == 2, "capture must be a no-op after opt-out")
    }

    @Test("loads previously stored consent on init")
    func loadsPersistedConsent() {
        let suiteName = "muxy.tests.analytics.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(AnalyticsConsent.allowed.rawValue, forKey: AnalyticsConsent.storageKey)

        let service = AnalyticsService(
            apiKey: "phc_test",
            defaults: defaults,
            starter: { _ in },
            stopper: {},
            capturer: { _, _ in }
        )

        #expect(service.consent == .allowed)
        #expect(!service.needsPrompt)
    }

    @Test("environment is derived from the injected defaults' update channel")
    func startContextEnvironmentReflectsChannel() {
        var capturedEnvironments: [String] = []
        let (service, defaults, suiteName) = makeService(
            apiKey: "phc_test",
            starter: { context in capturedEnvironments.append(context.environment) }
        )
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(UpdateChannel.beta.rawValue, forKey: UpdateChannel.storageKey)
        service.setConsent(.allowed)

        #expect(capturedEnvironments == ["beta"])
    }

    private func makeService(
        apiKey: String?,
        starter: @escaping (AnalyticsStartContext) -> Void = { _ in },
        stopper: @escaping () -> Void = {},
        capturer: @escaping (String, [String: String]) -> Void = { _, _ in }
    ) -> (AnalyticsService, UserDefaults, String) {
        let suiteName = "muxy.tests.analytics.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create isolated UserDefaults suite")
        }
        let service = AnalyticsService(
            apiKey: apiKey,
            defaults: defaults,
            starter: starter,
            stopper: stopper,
            capturer: capturer
        )
        return (service, defaults, suiteName)
    }
}

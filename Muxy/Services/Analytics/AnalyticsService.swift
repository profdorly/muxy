import Foundation
import os
import PostHog

private let logger = Logger(subsystem: "app.muxy", category: "Analytics")

enum AnalyticsEvent: String {
    case appLaunched = "app_launched"
    case extensionInstalled = "extension_installed"
}

struct AnalyticsStartContext {
    let apiKey: String
    let host: String
    let releaseName: String?
    let environment: String
}

@MainActor @Observable
final class AnalyticsService {
    static let shared = AnalyticsService()

    private static let defaultHost = "https://us.i.posthog.com"

    private(set) var consent: AnalyticsConsent?
    private var started = false

    let hasAPIKey: Bool
    private let apiKey: String?
    private let host: String
    private let defaults: UserDefaults
    private let starter: (AnalyticsStartContext) -> Void
    private let stopper: () -> Void
    private let capturer: (String, [String: String]) -> Void

    var needsPrompt: Bool {
        hasAPIKey && consent == nil
    }

    convenience init() {
        self.init(
            apiKey: Self.resolveBundledValue(for: "PostHogApiKey", placeholder: "__MUXY_POSTHOG_API_KEY__", debugKey: "POSTHOG_API_KEY"),
            host: Self.resolveBundledValue(for: "PostHogHost", placeholder: "__MUXY_POSTHOG_HOST__", debugKey: "POSTHOG_HOST")
                ?? Self.defaultHost,
            defaults: .standard,
            starter: Self.defaultStarter,
            stopper: Self.defaultStopper,
            capturer: Self.defaultCapturer
        )
    }

    init(
        apiKey: String?,
        host: String = AnalyticsService.defaultHost,
        defaults: UserDefaults,
        starter: @escaping (AnalyticsStartContext) -> Void,
        stopper: @escaping () -> Void,
        capturer: @escaping (String, [String: String]) -> Void
    ) {
        self.apiKey = apiKey
        hasAPIKey = apiKey != nil
        self.host = host
        self.defaults = defaults
        self.starter = starter
        self.stopper = stopper
        self.capturer = capturer
        consent = Self.loadStoredConsent(from: defaults)
    }

    func start() {
        guard hasAPIKey, let apiKey, consent == .allowed, !started else { return }
        let context = AnalyticsStartContext(
            apiKey: apiKey,
            host: host,
            releaseName: Self.releaseName,
            environment: Self.environment(from: defaults)
        )
        starter(context)
        started = true
        logger.info("Analytics started")
        capture(.appLaunched)
    }

    func stop() {
        guard started else { return }
        stopper()
        started = false
        logger.info("Analytics stopped")
    }

    func setConsent(_ newValue: AnalyticsConsent) {
        consent = newValue
        defaults.set(newValue.rawValue, forKey: AnalyticsConsent.storageKey)
        switch newValue {
        case .allowed:
            start()
        case .denied:
            stop()
        }
    }

    func capture(_ event: AnalyticsEvent, properties: [String: String] = [:]) {
        guard started, consent == .allowed else { return }
        capturer(event.rawValue, properties)
    }

    private static func loadStoredConsent(from defaults: UserDefaults) -> AnalyticsConsent? {
        guard let raw = defaults.string(forKey: AnalyticsConsent.storageKey) else { return nil }
        return AnalyticsConsent(rawValue: raw)
    }

    private static func resolveBundledValue(for key: String, placeholder: String, debugKey: String) -> String? {
        if let bundled = Bundle.main.object(forInfoDictionaryKey: key) as? String {
            let trimmed = bundled.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != placeholder {
                return trimmed
            }
        }
        #if DEBUG
        return DotEnvLoader.value(for: debugKey)
        #else
        return nil
        #endif
    }

    private static var releaseName: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private static func environment(from defaults: UserDefaults) -> String {
        let channel = defaults.string(forKey: UpdateChannel.storageKey)
            .flatMap { UpdateChannel(rawValue: $0) } ?? .stable
        return channel == .beta ? "beta" : "production"
    }

    private static let defaultStarter: (AnalyticsStartContext) -> Void = { context in
        let configuration = PostHogConfig(apiKey: context.apiKey, host: context.host)
        configuration.personProfiles = .never
        configuration.captureApplicationLifecycleEvents = false
        configuration.captureScreenViews = false
        configuration.preloadFeatureFlags = false
        PostHogSDK.shared.setup(configuration)
    }

    private static let defaultStopper: () -> Void = {
        PostHogSDK.shared.optOut()
    }

    private static let defaultCapturer: (String, [String: String]) -> Void = { event, properties in
        PostHogSDK.shared.capture(event, properties: properties)
    }
}

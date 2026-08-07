import Foundation

enum AnalyticsConsent: String {
    case allowed
    case denied

    static let storageKey = "muxy.analytics.consent"
}

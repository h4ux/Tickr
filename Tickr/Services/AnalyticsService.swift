import Foundation

/// Lightweight analytics using PostHog's REST API.
/// Tracks only: country (from locale) and stock add/remove events.
/// No personal data, no IP tracking, fully opt-out.
class AnalyticsService {
    static let shared = AnalyticsService()

    // PostHog project API key — loaded from Secrets.swift (git-ignored)
    // See Secrets.example.swift for setup instructions
    private static let apiKey = Secrets.postHogAPIKey
    private static let host = "https://us.i.posthog.com"
    private static let distinctIdKey = "analyticsDistinctId"

    private let distinctId: String

    /// All events that this app tracks — shown to users in the info panel
    static let trackedEvents: [(event: String, description: String)] = [
        ("app_opened", "App was launched"),
        ("stock_added", "A ticker symbol was added (symbol name + single/category)"),
        ("stock_removed", "A ticker symbol was removed (symbol name + single/category)"),
        ("category_created", "A new category was created (category name)"),
    ]

    /// Properties sent with every event
    static let commonProperties: [(property: String, description: String)] = [
        ("country", "Country code from your system locale (e.g. US, DE, JP)"),
        ("app_version", "Tickr version number"),
        ("os_version", "macOS version"),
    ]

    private init() {
        // Generate or retrieve anonymous ID
        if let stored = UserDefaults.standard.string(forKey: Self.distinctIdKey) {
            self.distinctId = stored
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: Self.distinctIdKey)
            self.distinctId = newId
        }
    }

    /// Track an event with optional properties
    func track(_ event: String, properties: [String: String] = [:]) {
        guard AppSettings.shared.analyticsEnabled else { return }
        guard Self.apiKey != "POSTHOG_API_KEY_PLACEHOLDER" else { return }

        var allProperties = properties
        allProperties["country"] = UserDefaults.standard.string(forKey: "userCountryCode")
            ?? Locale.current.region?.identifier ?? "unknown"
        allProperties["app_version"] = "1.0.0"
        allProperties["os_version"] = ProcessInfo.processInfo.operatingSystemVersionString
        // PostHog expects $lib for identification
        allProperties["$lib"] = "swift"

        let body: [String: Any] = [
            "api_key": Self.apiKey,
            "event": event,
            "distinct_id": distinctId,
            "properties": allProperties,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]

        guard let url = URL(string: "\(Self.host)/capture/"),
              let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        // Use URLSession.shared — it persists for the app lifetime
        // Custom sessions can be deallocated, dropping in-flight requests
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    /// Called when user opts out — clears the anonymous ID
    func optOut() {
        UserDefaults.standard.removeObject(forKey: Self.distinctIdKey)
    }

    /// Track app launch
    func trackAppOpen() {
        track("app_opened")
    }
}

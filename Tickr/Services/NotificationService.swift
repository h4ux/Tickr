import Foundation
import UserNotifications
import AppKit
import Combine

class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var alertSetting: UNNotificationSetting = .notSupported
    @Published var soundSetting: UNNotificationSetting = .notSupported
    @Published var notificationCenterSetting: UNNotificationSetting = .notSupported
    @Published var lastError: String?

    private let settings = AppSettings.shared
    private var cancellables = Set<AnyCancellable>()

    /// Symbol → date of last alert (used to avoid spamming the same alert multiple times per day).
    private var alertedToday: [String: Date] = [:]

    private override init() {
        super.init()
        refreshStatus()

        // React to fresh quotes from StockService
        StockService.shared.$quotes
            .dropFirst()
            .sink { [weak self] quotes in
                self?.evaluate(quotes: quotes)
            }
            .store(in: &cancellables)
    }

    // MARK: - Authorization

    func refreshStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] s in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.authorizationStatus = s.authorizationStatus
                self.alertSetting = s.alertSetting
                self.soundSetting = s.soundSetting
                self.notificationCenterSetting = s.notificationCenterSetting
                // Clear stale errors once we know notifications are usable.
                if self.isAuthorized {
                    self.lastError = nil
                }
            }
        }
    }

    /// True only when authorization is granted AND alert banners are enabled.
    var bannersEnabled: Bool {
        isAuthorized && alertSetting == .enabled
    }

    /// Request permission. macOS prompts only once; subsequent calls return the saved decision.
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.refreshStatus()
                if let error = error {
                    self?.lastError = error.localizedDescription
                }
                completion(granted)
            }
        }
    }

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    var statusDescription: String {
        switch authorizationStatus {
        case .notDetermined: return "Not requested"
        case .denied:        return "Denied"
        case .authorized:    return "Granted"
        case .provisional:   return "Granted (provisional)"
        case .ephemeral:     return "Granted (ephemeral)"
        @unknown default:    return "Unknown"
        }
    }

    func openSystemSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications",
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    // MARK: - Sending

    private func send(title: String, body: String, identifier: String = UUID().uuidString) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Treat sub-second deliveries as time-sensitive on supported macOS so the system
        // is more likely to show them as a banner instead of silently filing in NC.
        if #available(macOS 12.0, *) {
            content.interruptionLevel = .active
        }
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.lastError = error.localizedDescription
                }
                // Refresh settings — `add()` errors are most often "alert style off",
                // and reading settings tells us whether to nudge the user about it.
                self?.refreshStatus()
            }
        }
    }

    func sendTestNotification() {
        send(title: "Tickr", body: "Notifications are working ✓", identifier: "tickr-test-\(UUID().uuidString)")
    }

    // MARK: - Criteria evaluation

    func evaluate(quotes: [StockQuote]) {
        guard settings.notificationsEnabled, isAuthorized else { return }
        guard settings.notifyOnPriceChangeEnabled else { return }

        let threshold = abs(settings.priceChangePercentThreshold)
        guard threshold > 0 else { return }

        let today = Calendar.current.startOfDay(for: Date())

        for q in quotes {
            let pct = abs(q.changePercent)
            guard pct >= threshold else { continue }

            // Already alerted today for this symbol?
            if let lastDate = alertedToday[q.symbol],
               Calendar.current.isDate(lastDate, inSameDayAs: today) {
                continue
            }
            alertedToday[q.symbol] = Date()

            let arrow = q.isUp ? "▲" : "▼"
            let sign = q.isUp ? "+" : ""
            let title = "\(q.symbol) \(arrow) \(sign)\(String(format: "%.2f", q.changePercent))%"
            let body = "\(q.shortCompanyName) at \(String(format: "%.2f", q.price)) \(q.currency)"
            send(title: title, body: body, identifier: "tickr-pricealert-\(q.symbol)-\(today.timeIntervalSince1970)")
        }
    }
}

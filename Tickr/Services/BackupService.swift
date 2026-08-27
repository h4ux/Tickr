import Foundation
import AppKit

// MARK: - Backup parts

/// One slice of the app's state. Drives both the export picker and the
/// import picker so the two always offer the same granularity.
enum BackupPart: String, Codable, CaseIterable, Identifiable {
    case preferences
    case watchlist
    case todos
    case clipboard
    case sec
    case license

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preferences: return "Preferences"
        case .watchlist:   return "Watchlist"
        case .todos:       return "Todos"
        case .clipboard:   return "Clipboard History"
        case .sec:         return "SEC Filings Cache"
        case .license:     return "License"
        }
    }

    var icon: String {
        switch self {
        case .preferences: return "gearshape"
        case .watchlist:   return "chart.line.uptrend.xyaxis"
        case .todos:       return "checklist"
        case .clipboard:   return "doc.on.clipboard"
        case .sec:         return "doc.text.magnifyingglass"
        case .license:     return "key.fill"
        }
    }

    var explanation: String {
        switch self {
        case .preferences: return "Display, refresh, rotation, notifications, shortcuts, SEC and analytics settings"
        case .watchlist:   return "Tickers, categories, holdings, sort orders and CIK mappings"
        case .todos:       return "Every todo, including done and archived items"
        case .clipboard:   return "Saved clipboard entries (images make the file large)"
        case .sec:         return "Downloaded filings and parsed insider details — re-fetchable"
        case .license:     return "Licensed email and key"
        }
    }
}

/// What a backup (either the live app state or a loaded file) holds, per part.
struct BackupSummary: Identifiable {
    let part: BackupPart
    /// nil when the part isn't present in the file at all.
    let detail: String?

    var id: String { part.rawValue }
    var isAvailable: Bool { detail != nil }
}

// MARK: - Backup document

/// The on-disk format. Every field is optional so a file written by another
/// version — or one the user hand-edited — still decodes.
struct TickrBackup: Codable {
    static let formatIdentifier = "tickr-backup"
    static let currentVersion = 1

    var format: String
    var version: Int
    var exportedAt: Date
    var appVersion: String

    var preferences: Preferences?
    var watchlist: Watchlist?
    var todos: [TodoItem]?
    var clipboard: [ClipboardItem]?
    var sec: SECData?
    var license: License?

    // MARK: Nested payloads

    struct Preferences: Codable {
        var refreshInterval: Double?
        var displayFormat: Int?
        var trendStyle: Int?
        var colorMode: Int?
        var detailLevel: Int?
        var showGraph: Bool?
        var showMarketCap: Bool?
        var showHoldings: Bool?
        var menuBarMaxWidth: Double?
        var showAdsWhenLicensed: Bool?
        var analyticsEnabled: Bool?
        var autoCheckForUpdates: Bool?

        var rotatingSymbols: [String]?
        var rotationEnabled: Bool?
        var rotationInterval: Double?
        var rotationMode: String?

        var notificationsEnabled: Bool?
        var notifyOnPriceChangeEnabled: Bool?
        var priceChangePercentThreshold: Double?

        var clipboardEnabled: Bool?
        var clipboardHistoryLimit: Int?
        var clipboardShortcutEnabled: Bool?
        var clipboardSyncEnabled: Bool?
        var clipboardSyncKey: String?
        var clipboardWindowWidth: Int?
        var clipboardWindowHeight: Int?
        var clipboardShortcutKeyCode: UInt32?
        var clipboardShortcutModifiers: UInt32?

        var todoEnabled: Bool?
        var todoShortcutEnabled: Bool?
        var todoShortcutKeyCode: UInt32?
        var todoShortcutModifiers: UInt32?
        var todoWindowWidth: Int?
        var todoWindowHeight: Int?
        var todoSyncEnabled: Bool?

        var secUserAgentName: String?
        var secUserAgentEmail: String?
        var secPollingEnabled: Bool?
        var secPollingIntervalMinutes: Int?
        var secDateRangeDays: Int?
        var secNotifyOnNewFilings: Bool?
    }

    struct Watchlist: Codable {
        var items: [TickerItem]?
        var primarySymbol: String?
        var holdings: [String: Double]?
        var categorySortOrders: [String: Int]?
        var symbolCIKMap: [String: String]?
    }

    struct SECData: Codable {
        var filings: [String: [FilingItem]]?
        var seenAccessions: [String: [String]]?
        var insiderCache: [String: FilingItem.InsiderInfo]?
    }

    struct License: Codable {
        var email: String
        var key: String
    }

    /// Which parts this document actually carries.
    var presentParts: Set<BackupPart> {
        var parts = Set<BackupPart>()
        if preferences != nil { parts.insert(.preferences) }
        if watchlist != nil   { parts.insert(.watchlist) }
        if todos != nil       { parts.insert(.todos) }
        if clipboard != nil   { parts.insert(.clipboard) }
        if sec != nil         { parts.insert(.sec) }
        if license != nil     { parts.insert(.license) }
        return parts
    }
}

// MARK: - Errors

enum BackupError: LocalizedError {
    case unreadable
    case notABackup
    case newerFormat(Int)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "That file couldn't be read as a Tickr backup."
        case .notABackup:
            return "That file isn't a Tickr backup."
        case .newerFormat(let v):
            return "This backup was written by a newer version of Tickr (format \(v)). Update Tickr and try again."
        }
    }
}

// MARK: - Service

/// Reads and writes a single JSON document holding every setting and every
/// piece of user data the app persists. Both directions are part-selectable
/// so a user can, say, carry their watchlist to another Mac without dragging
/// along a few hundred clipboard screenshots.
class BackupService: ObservableObject {
    static let shared = BackupService()

    private init() {}

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - Building

    /// Snapshot the live app state for the requested parts.
    func makeBackup(parts: Set<BackupPart>) -> TickrBackup {
        let settings = AppSettings.shared

        var backup = TickrBackup(
            format: TickrBackup.formatIdentifier,
            version: TickrBackup.currentVersion,
            exportedAt: Date(),
            appVersion: UpdateService.currentVersion
        )

        if parts.contains(.preferences) {
            backup.preferences = TickrBackup.Preferences(
                refreshInterval: settings.refreshInterval,
                displayFormat: settings.displayFormat.rawValue,
                trendStyle: settings.trendStyle.rawValue,
                colorMode: settings.colorMode.rawValue,
                detailLevel: settings.detailLevel.rawValue,
                showGraph: settings.showGraph,
                showMarketCap: settings.showMarketCap,
                showHoldings: settings.showHoldings,
                menuBarMaxWidth: settings.menuBarMaxWidth,
                showAdsWhenLicensed: settings.showAdsWhenLicensed,
                analyticsEnabled: settings.analyticsEnabled,
                autoCheckForUpdates: UpdateService.shared.autoCheckEnabled,
                rotatingSymbols: settings.rotatingSymbols,
                rotationEnabled: settings.rotationEnabled,
                rotationInterval: settings.rotationInterval,
                rotationMode: settings.rotationMode.rawValue,
                notificationsEnabled: settings.notificationsEnabled,
                notifyOnPriceChangeEnabled: settings.notifyOnPriceChangeEnabled,
                priceChangePercentThreshold: settings.priceChangePercentThreshold,
                clipboardEnabled: settings.clipboardEnabled,
                clipboardHistoryLimit: settings.clipboardHistoryLimit,
                clipboardShortcutEnabled: settings.clipboardShortcutEnabled,
                clipboardSyncEnabled: settings.clipboardSyncEnabled,
                clipboardSyncKey: settings.clipboardSyncKey,
                clipboardWindowWidth: settings.clipboardWindowWidth,
                clipboardWindowHeight: settings.clipboardWindowHeight,
                clipboardShortcutKeyCode: settings.clipboardShortcutKeyCode,
                clipboardShortcutModifiers: settings.clipboardShortcutModifiers,
                todoEnabled: settings.todoEnabled,
                todoShortcutEnabled: settings.todoShortcutEnabled,
                todoShortcutKeyCode: settings.todoShortcutKeyCode,
                todoShortcutModifiers: settings.todoShortcutModifiers,
                todoWindowWidth: settings.todoWindowWidth,
                todoWindowHeight: settings.todoWindowHeight,
                todoSyncEnabled: settings.todoSyncEnabled,
                secUserAgentName: settings.secUserAgentName,
                secUserAgentEmail: settings.secUserAgentEmail,
                secPollingEnabled: settings.secPollingEnabled,
                secPollingIntervalMinutes: settings.secPollingIntervalMinutes,
                secDateRangeDays: settings.secDateRangeDays,
                secNotifyOnNewFilings: settings.secNotifyOnNewFilings
            )
        }

        if parts.contains(.watchlist) {
            backup.watchlist = TickrBackup.Watchlist(
                items: settings.items,
                primarySymbol: settings.primarySymbol,
                holdings: settings.holdings,
                categorySortOrders: settings.categorySortOrders,
                symbolCIKMap: settings.secSymbolCIKMap
            )
        }

        if parts.contains(.todos) {
            backup.todos = TodoService.shared.items
        }

        if parts.contains(.clipboard) {
            backup.clipboard = ClipboardService.shared.items
        }

        if parts.contains(.sec) {
            let snapshot = SECService.shared.exportSnapshot()
            backup.sec = TickrBackup.SECData(
                filings: snapshot.filings,
                seenAccessions: snapshot.seenAccessions,
                insiderCache: snapshot.insiderCache
            )
        }

        if parts.contains(.license), LicenseService.shared.isLicensed {
            let email = UserDefaults.standard.string(forKey: "licenseEmail") ?? ""
            let key = UserDefaults.standard.string(forKey: "licenseKey") ?? ""
            if !email.isEmpty && !key.isEmpty {
                backup.license = TickrBackup.License(email: email, key: key)
            }
        }

        return backup
    }

    // MARK: - Summaries

    /// What the live app would put in each part right now.
    func currentSummaries() -> [BackupSummary] {
        let settings = AppSettings.shared
        let tickerCount = settings.allSymbols.count
        let categoryCount = settings.items.filter { $0.isCategory }.count
        let secSnapshot = SECService.shared.exportSnapshot()
        let filingCount = secSnapshot.filings.values.reduce(0) { $0 + $1.count }

        return BackupPart.allCases.map { part in
            switch part {
            case .preferences:
                return BackupSummary(part: part, detail: "All app settings")
            case .watchlist:
                return BackupSummary(part: part, detail: "\(tickerCount) \(plural(tickerCount, "ticker")), \(categoryCount) \(plural(categoryCount, "category", "categories"))")
            case .todos:
                let n = TodoService.shared.items.count
                return BackupSummary(part: part, detail: "\(n) \(plural(n, "item"))")
            case .clipboard:
                let n = ClipboardService.shared.items.count
                return BackupSummary(part: part, detail: "\(n) \(plural(n, "entry", "entries"))")
            case .sec:
                return BackupSummary(part: part, detail: "\(filingCount) \(plural(filingCount, "filing"))")
            case .license:
                return BackupSummary(part: part, detail: LicenseService.shared.isLicensed
                    ? LicenseService.shared.licensedEmail
                    : nil)
            }
        }
    }

    /// What a loaded file holds. Parts missing from the file get a nil detail.
    func summaries(for backup: TickrBackup) -> [BackupSummary] {
        BackupPart.allCases.map { part in
            switch part {
            case .preferences:
                return BackupSummary(part: part, detail: backup.preferences == nil ? nil : "All app settings")
            case .watchlist:
                guard let w = backup.watchlist else { return BackupSummary(part: part, detail: nil) }
                let symbols = (w.items ?? []).flatMap { $0.allSymbols }.count
                let cats = (w.items ?? []).filter { $0.isCategory }.count
                return BackupSummary(part: part, detail: "\(symbols) \(plural(symbols, "ticker")), \(cats) \(plural(cats, "category", "categories"))")
            case .todos:
                guard let t = backup.todos else { return BackupSummary(part: part, detail: nil) }
                return BackupSummary(part: part, detail: "\(t.count) \(plural(t.count, "item"))")
            case .clipboard:
                guard let c = backup.clipboard else { return BackupSummary(part: part, detail: nil) }
                return BackupSummary(part: part, detail: "\(c.count) \(plural(c.count, "entry", "entries"))")
            case .sec:
                guard let s = backup.sec else { return BackupSummary(part: part, detail: nil) }
                let n = (s.filings ?? [:]).values.reduce(0) { $0 + $1.count }
                return BackupSummary(part: part, detail: "\(n) \(plural(n, "filing"))")
            case .license:
                guard let l = backup.license else { return BackupSummary(part: part, detail: nil) }
                return BackupSummary(part: part, detail: l.email)
            }
        }
    }

    private func plural(_ n: Int, _ singular: String, _ pluralForm: String? = nil) -> String {
        n == 1 ? singular : (pluralForm ?? singular + "s")
    }

    // MARK: - Export

    func encode(parts: Set<BackupPart>) throws -> Data {
        try Self.encoder.encode(makeBackup(parts: parts))
    }

    /// Show a Save panel and write the selected parts to disk.
    /// `completion` receives an error message, or nil on success/cancel.
    func exportToFile(parts: Set<BackupPart>, completion: @escaping (String?) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = Self.suggestedFilename()
        panel.title = "Export Tickr Backup"
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                completion(nil)
                return
            }
            do {
                let data = try self.encode(parts: parts)
                try data.write(to: url, options: .atomic)
                AnalyticsService.shared.track("backup_exported", properties: [
                    "parts": parts.map(\.rawValue).sorted().joined(separator: ","),
                    "bytes": String(data.count),
                ])
                completion(nil)
            } catch {
                completion(error.localizedDescription)
            }
        }
    }

    static func suggestedFilename() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "Tickr-Backup-\(f.string(from: Date())).json"
    }

    // MARK: - Import

    /// Show an Open panel and decode the chosen file. `completion` gets nil
    /// if the user cancelled.
    func pickBackupFile(completion: @escaping (Result<TickrBackup, Error>?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Tickr Backup"
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                completion(nil)
                return
            }
            completion(Result { try self.load(from: url) })
        }
    }

    func load(from url: URL) throws -> TickrBackup {
        guard let data = try? Data(contentsOf: url) else { throw BackupError.unreadable }
        guard let backup = try? Self.decoder.decode(TickrBackup.self, from: data) else {
            throw BackupError.notABackup
        }
        guard backup.format == TickrBackup.formatIdentifier else { throw BackupError.notABackup }
        guard backup.version <= TickrBackup.currentVersion else {
            throw BackupError.newerFormat(backup.version)
        }
        return backup
    }

    /// Apply the selected parts of a backup, replacing whatever is there now.
    /// Returns human-readable warnings for anything that couldn't be applied.
    @discardableResult
    func apply(_ backup: TickrBackup, parts: Set<BackupPart>) -> [String] {
        let settings = AppSettings.shared
        var warnings: [String] = []

        if parts.contains(.preferences), let p = backup.preferences {
            if let v = p.refreshInterval, v > 0 { settings.refreshInterval = v }
            if let v = p.displayFormat, let f = TickerDisplayFormat(rawValue: v) { settings.displayFormat = f }
            if let v = p.trendStyle, let t = TickerTrendStyle(rawValue: v) { settings.trendStyle = t }
            if let v = p.colorMode, let c = TickerColorMode(rawValue: v) { settings.colorMode = c }
            if let v = p.detailLevel, let d = DropdownDetailLevel(rawValue: v) { settings.detailLevel = d }
            if let v = p.showGraph { settings.showGraph = v }
            if let v = p.showMarketCap { settings.showMarketCap = v }
            if let v = p.showHoldings { settings.showHoldings = v }
            if let v = p.menuBarMaxWidth { settings.menuBarMaxWidth = v }
            if let v = p.showAdsWhenLicensed { settings.showAdsWhenLicensed = v }
            if let v = p.analyticsEnabled { settings.analyticsEnabled = v }
            if let v = p.autoCheckForUpdates { UpdateService.shared.autoCheckEnabled = v }

            if let v = p.rotatingSymbols { settings.rotatingSymbols = v }
            if let v = p.rotationEnabled { settings.rotationEnabled = v }
            if let v = p.rotationInterval, v > 0 { settings.rotationInterval = v }
            if let v = p.rotationMode, let m = RotationMode(rawValue: v) { settings.rotationMode = m }

            if let v = p.notificationsEnabled { settings.notificationsEnabled = v }
            if let v = p.notifyOnPriceChangeEnabled { settings.notifyOnPriceChangeEnabled = v }
            if let v = p.priceChangePercentThreshold, v > 0 { settings.priceChangePercentThreshold = v }

            if let v = p.clipboardEnabled { settings.clipboardEnabled = v }
            if let v = p.clipboardHistoryLimit, v > 0 { settings.clipboardHistoryLimit = v }
            if let v = p.clipboardShortcutEnabled { settings.clipboardShortcutEnabled = v }
            if let v = p.clipboardSyncEnabled { settings.clipboardSyncEnabled = v }
            if let v = p.clipboardSyncKey { settings.clipboardSyncKey = v }
            if let v = p.clipboardWindowWidth, v > 0 { settings.clipboardWindowWidth = v }
            if let v = p.clipboardWindowHeight, v > 0 { settings.clipboardWindowHeight = v }
            if let v = p.clipboardShortcutKeyCode, v > 0 { settings.clipboardShortcutKeyCode = v }
            if let v = p.clipboardShortcutModifiers, v > 0 { settings.clipboardShortcutModifiers = v }

            if let v = p.todoEnabled { settings.todoEnabled = v }
            if let v = p.todoShortcutEnabled { settings.todoShortcutEnabled = v }
            if let v = p.todoShortcutKeyCode, v > 0 { settings.todoShortcutKeyCode = v }
            if let v = p.todoShortcutModifiers, v > 0 { settings.todoShortcutModifiers = v }
            if let v = p.todoWindowWidth, v > 0 { settings.todoWindowWidth = v }
            if let v = p.todoWindowHeight, v > 0 { settings.todoWindowHeight = v }
            if let v = p.todoSyncEnabled { settings.todoSyncEnabled = v }

            if let v = p.secUserAgentName { settings.secUserAgentName = v }
            if let v = p.secUserAgentEmail { settings.secUserAgentEmail = v }
            if let v = p.secPollingEnabled { settings.secPollingEnabled = v }
            if let v = p.secPollingIntervalMinutes, v > 0 { settings.secPollingIntervalMinutes = v }
            if let v = p.secDateRangeDays, v > 0 { settings.secDateRangeDays = v }
            if let v = p.secNotifyOnNewFilings { settings.secNotifyOnNewFilings = v }
        }

        if parts.contains(.watchlist), let w = backup.watchlist {
            if let items = w.items { settings.items = items }
            if let holdings = w.holdings { settings.holdings = holdings }
            if let orders = w.categorySortOrders { settings.categorySortOrders = orders }
            if let map = w.symbolCIKMap { settings.secSymbolCIKMap = map }

            // Keep the menu bar pointing at something that still exists.
            let symbols = settings.allSymbols
            if let primary = w.primarySymbol, symbols.contains(primary) {
                settings.primarySymbol = primary
            } else if !symbols.contains(settings.primarySymbol) {
                settings.primarySymbol = symbols.first ?? ""
            }
            settings.rotatingSymbols = settings.rotatingSymbols.filter { symbols.contains($0) }

            StockService.shared.fetchQuotes()
        }

        if parts.contains(.todos) {
            if let todos = backup.todos {
                TodoService.shared.replaceAll(todos)
            } else {
                warnings.append("No todos in this backup.")
            }
        }

        if parts.contains(.clipboard) {
            if let clipboard = backup.clipboard {
                ClipboardService.shared.replaceAll(clipboard)
            } else {
                warnings.append("No clipboard history in this backup.")
            }
        }

        if parts.contains(.sec), let s = backup.sec {
            SECService.shared.importSnapshot(
                filings: s.filings ?? [:],
                seenAccessions: (s.seenAccessions ?? [:]).mapValues { Set($0) },
                insiderCache: s.insiderCache ?? [:]
            )
        }

        if parts.contains(.license), let l = backup.license {
            if !LicenseService.shared.activate(email: l.email, key: l.key) {
                warnings.append("The license in this backup isn't valid — it wasn't applied.")
            }
        }

        AnalyticsService.shared.track("backup_imported", properties: [
            "parts": parts.map(\.rawValue).sorted().joined(separator: ","),
            "warnings": String(warnings.count),
        ])

        return warnings
    }
}

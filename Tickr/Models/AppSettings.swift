import Foundation
import Combine

// MARK: - Display enums

enum TickerDisplayFormat: Int, CaseIterable {
    case tickerAndPrice = 0
    case priceOnly = 1
    case companyAndPrice = 2
    case tickerPriceAndChange = 3
    case companyPriceAndChange = 4

    var label: String {
        switch self {
        case .tickerAndPrice:        return "Ticker + Price"
        case .priceOnly:             return "Price Only"
        case .companyAndPrice:       return "Company + Price"
        case .tickerPriceAndChange:  return "Ticker + Price + Change"
        case .companyPriceAndChange: return "Company + Price + Change"
        }
    }
}

enum TickerTrendStyle: Int, CaseIterable {
    case none = 0
    case arrow = 1
    case arrowWithPercent = 2
    case percentOnly = 3

    var label: String {
        switch self {
        case .none:             return "None"
        case .arrow:            return "Arrow (▲ / ▼)"
        case .arrowWithPercent: return "Arrow + Percent"
        case .percentOnly:      return "Percent Only"
        }
    }
}

enum TickerColorMode: Int, CaseIterable {
    case colored = 0
    case grey = 1
    case sectional = 2
    case accent = 3
    case bold = 4

    var label: String {
        switch self {
        case .colored:   return "Green / Red"
        case .grey:      return "Grey (monochrome)"
        case .sectional: return "Per section"
        case .accent:    return "Accent color"
        case .bold:      return "Bold ticker, colored change"
        }
    }
}

enum ChartRange: String, CaseIterable {
    case week = "5d"
    case month = "1mo"
    case ytd = "ytd"
    case year = "1y"
    case fiveYears = "5y"

    var label: String {
        switch self {
        case .week:      return "1W"
        case .month:     return "1M"
        case .ytd:       return "YTD"
        case .year:      return "1Y"
        case .fiveYears: return "5Y"
        }
    }

    var interval: String {
        switch self {
        case .week:      return "15m"
        case .month:     return "1d"
        case .ytd:       return "1d"
        case .year:      return "1wk"
        case .fiveYears: return "1mo"
        }
    }
}

enum CategorySortOrder: Int, CaseIterable {
    case manual = 0
    case nameAsc = 1
    case nameDesc = 2
    case changeDesc = 3
    case changeAsc = 4
    case priceDesc = 5
    case priceAsc = 6

    var label: String {
        switch self {
        case .manual:     return "Manual (drag order)"
        case .nameAsc:    return "Name (A → Z)"
        case .nameDesc:   return "Name (Z → A)"
        case .changeDesc: return "Change % (best first)"
        case .changeAsc:  return "Change % (worst first)"
        case .priceDesc:  return "Price (high → low)"
        case .priceAsc:   return "Price (low → high)"
        }
    }
}

enum RotationMode: String, CaseIterable {
    case swap      // change shown ticker every N seconds
    case scroll    // continuously scroll all tickers across the menu bar

    var label: String {
        switch self {
        case .swap:   return "Change every interval"
        case .scroll: return "Scroll continuously"
        }
    }
}

enum DropdownDetailLevel: Int, CaseIterable {
    case compact = 0
    case standard = 1
    case detailed = 2

    var label: String {
        switch self {
        case .compact:  return "Compact (price + change only)"
        case .standard: return "Standard (+ market cap, volume)"
        case .detailed: return "Detailed (+ ranges, 52W bar, sector)"
        }
    }
}

// MARK: - Ticker Items

struct TickerItem: Codable, Identifiable {
    let id: UUID
    var kind: Kind

    enum Kind: Codable {
        case single(symbol: String)
        case category(name: String, icon: String, symbols: [String])
    }

    var allSymbols: [String] {
        switch kind {
        case .single(let symbol):
            return [symbol]
        case .category(_, _, let symbols):
            return symbols
        }
    }

    var displayName: String {
        switch kind {
        case .single(let symbol):
            return symbol
        case .category(let name, _, _):
            return name
        }
    }

    var isCategory: Bool {
        if case .category = kind { return true }
        return false
    }

    static func single(_ symbol: String) -> TickerItem {
        TickerItem(id: UUID(), kind: .single(symbol: symbol))
    }

    static func category(_ name: String, icon: String = "folder", symbols: [String] = []) -> TickerItem {
        TickerItem(id: UUID(), kind: .category(name: name, icon: icon, symbols: symbols))
    }
}

// MARK: - App Settings

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private static let itemsKey = "tickerItems"
    private static let primarySymbolKey = "primarySymbol"
    private static let refreshIntervalKey = "refreshInterval"
    private static let displayFormatKey = "displayFormat"
    private static let trendStyleKey = "trendStyle"
    private static let colorModeKey = "colorMode"
    private static let analyticsEnabledKey = "analyticsEnabled"
    private static let detailLevelKey = "detailLevel"
    private static let showGraphKey = "showGraph"
    private static let categorySortKey = "categorySortOrders"
    private static let showAdsKey = "showAdsWhenLicensed"
    private static let holdingsKey = "stockHoldings"
    private static let showHoldingsKey = "showHoldings"
    private static let rotatingSymbolsKey = "rotatingSymbols"
    private static let rotationEnabledKey = "rotationEnabled"
    private static let rotationIntervalKey = "rotationInterval"
    private static let rotationModeKey = "rotationMode"
    private static let notificationsEnabledKey = "notificationsEnabled"
    private static let notifyOnPriceChangeKey = "notifyOnPriceChange"
    private static let priceChangeThresholdKey = "priceChangePercentThreshold"
    private static let clipboardEnabledKey = "clipboardEnabled"
    private static let clipboardHistoryLimitKey = "clipboardHistoryLimit"
    private static let clipboardSyncEnabledKey = "clipboardSyncEnabled"
    private static let clipboardSyncKeyKey = "clipboardSyncKey"
    private static let clipboardShortcutEnabledKey = "clipboardShortcutEnabled"
    private static let clipboardWindowWidthKey = "clipboardWindowWidth"
    private static let clipboardWindowHeightKey = "clipboardWindowHeight"
    private static let clipboardShortcutKeyCodeKey = "clipboardShortcutKeyCode"
    private static let clipboardShortcutModifiersKey = "clipboardShortcutModifiers"
    private static let todoEnabledKey = "todoEnabled"
    private static let todoShortcutEnabledKey = "todoShortcutEnabled"
    private static let todoShortcutKeyCodeKey = "todoShortcutKeyCode"
    private static let todoShortcutModifiersKey = "todoShortcutModifiers"
    private static let todoWindowWidthKey = "todoWindowWidth"
    private static let todoWindowHeightKey = "todoWindowHeight"
    private static let todoSyncEnabledKey = "todoSyncEnabled"
    private static let showMarketCapKey = "showMarketCap"
    private static let menuBarMaxWidthKey = "menuBarMaxWidth"

    // Legacy key for migration
    private static let legacySymbolsKey = "watchedSymbols"

    static let maxSymbols = 999  // No practical limit
    static let categoryIcons = [
        "folder", "chart.line.uptrend.xyaxis", "laptopcomputer", "building.2",
        "cross.case", "bolt", "leaf", "car", "airplane", "banknote",
        "globe", "cpu", "gamecontroller", "film", "cart", "moon.stars",
    ]
    static let refreshIntervals: [(label: String, seconds: TimeInterval)] = [
        ("15 seconds", 15),
        ("30 seconds", 30),
        ("1 minute", 60),
        ("5 minutes", 300),
        ("15 minutes", 900),
        ("30 minutes", 1800),
    ]

    @Published var items: [TickerItem] {
        didSet { saveItems() }
    }

    @Published var primarySymbol: String {
        didSet {
            UserDefaults.standard.set(primarySymbol, forKey: Self.primarySymbolKey)
        }
    }

    @Published var refreshInterval: TimeInterval {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: Self.refreshIntervalKey)
        }
    }

    @Published var displayFormat: TickerDisplayFormat {
        didSet {
            UserDefaults.standard.set(displayFormat.rawValue, forKey: Self.displayFormatKey)
        }
    }

    @Published var trendStyle: TickerTrendStyle {
        didSet {
            UserDefaults.standard.set(trendStyle.rawValue, forKey: Self.trendStyleKey)
        }
    }

    @Published var colorMode: TickerColorMode {
        didSet {
            UserDefaults.standard.set(colorMode.rawValue, forKey: Self.colorModeKey)
        }
    }

    @Published var detailLevel: DropdownDetailLevel {
        didSet {
            UserDefaults.standard.set(detailLevel.rawValue, forKey: Self.detailLevelKey)
        }
    }

    @Published var showGraph: Bool {
        didSet {
            UserDefaults.standard.set(showGraph, forKey: Self.showGraphKey)
        }
    }

    /// Rotating tickers in menu bar (up to 5)
    @Published var rotatingSymbols: [String] {
        didSet {
            UserDefaults.standard.set(rotatingSymbols, forKey: Self.rotatingSymbolsKey)
        }
    }

    @Published var rotationEnabled: Bool {
        didSet {
            UserDefaults.standard.set(rotationEnabled, forKey: Self.rotationEnabledKey)
        }
    }

    @Published var rotationInterval: TimeInterval {
        didSet {
            UserDefaults.standard.set(rotationInterval, forKey: Self.rotationIntervalKey)
        }
    }

    @Published var rotationMode: RotationMode {
        didSet {
            UserDefaults.standard.set(rotationMode.rawValue, forKey: Self.rotationModeKey)
        }
    }

    @Published var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: Self.notificationsEnabledKey)
        }
    }

    @Published var notifyOnPriceChangeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notifyOnPriceChangeEnabled, forKey: Self.notifyOnPriceChangeKey)
        }
    }

    @Published var priceChangePercentThreshold: Double {
        didSet {
            UserDefaults.standard.set(priceChangePercentThreshold, forKey: Self.priceChangeThresholdKey)
        }
    }

    // MARK: Bonus features — clipboard

    @Published var clipboardEnabled: Bool {
        didSet { UserDefaults.standard.set(clipboardEnabled, forKey: Self.clipboardEnabledKey) }
    }

    @Published var clipboardHistoryLimit: Int {
        didSet { UserDefaults.standard.set(clipboardHistoryLimit, forKey: Self.clipboardHistoryLimitKey) }
    }

    @Published var clipboardShortcutEnabled: Bool {
        didSet { UserDefaults.standard.set(clipboardShortcutEnabled, forKey: Self.clipboardShortcutEnabledKey) }
    }

    @Published var clipboardSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(clipboardSyncEnabled, forKey: Self.clipboardSyncEnabledKey) }
    }

    @Published var clipboardSyncKey: String {
        didSet { UserDefaults.standard.set(clipboardSyncKey, forKey: Self.clipboardSyncKeyKey) }
    }

    @Published var clipboardWindowWidth: Int {
        didSet { UserDefaults.standard.set(clipboardWindowWidth, forKey: Self.clipboardWindowWidthKey) }
    }

    @Published var clipboardWindowHeight: Int {
        didSet { UserDefaults.standard.set(clipboardWindowHeight, forKey: Self.clipboardWindowHeightKey) }
    }

    @Published var clipboardShortcutKeyCode: UInt32 {
        didSet { UserDefaults.standard.set(Int(clipboardShortcutKeyCode), forKey: Self.clipboardShortcutKeyCodeKey) }
    }

    @Published var clipboardShortcutModifiers: UInt32 {
        didSet { UserDefaults.standard.set(Int(clipboardShortcutModifiers), forKey: Self.clipboardShortcutModifiersKey) }
    }

    // MARK: Bonus features — todo

    @Published var todoEnabled: Bool {
        didSet { UserDefaults.standard.set(todoEnabled, forKey: Self.todoEnabledKey) }
    }

    @Published var todoShortcutEnabled: Bool {
        didSet { UserDefaults.standard.set(todoShortcutEnabled, forKey: Self.todoShortcutEnabledKey) }
    }

    @Published var todoShortcutKeyCode: UInt32 {
        didSet { UserDefaults.standard.set(Int(todoShortcutKeyCode), forKey: Self.todoShortcutKeyCodeKey) }
    }

    @Published var todoShortcutModifiers: UInt32 {
        didSet { UserDefaults.standard.set(Int(todoShortcutModifiers), forKey: Self.todoShortcutModifiersKey) }
    }

    @Published var todoWindowWidth: Int {
        didSet { UserDefaults.standard.set(todoWindowWidth, forKey: Self.todoWindowWidthKey) }
    }

    @Published var todoWindowHeight: Int {
        didSet { UserDefaults.standard.set(todoWindowHeight, forKey: Self.todoWindowHeightKey) }
    }

    @Published var todoSyncEnabled: Bool {
        didSet { UserDefaults.standard.set(todoSyncEnabled, forKey: Self.todoSyncEnabledKey) }
    }

    @Published var showMarketCap: Bool {
        didSet {
            UserDefaults.standard.set(showMarketCap, forKey: Self.showMarketCapKey)
        }
    }

    /// Menu bar width in points. 0 = auto (variable length).
    @Published var menuBarMaxWidth: Double {
        didSet {
            UserDefaults.standard.set(menuBarMaxWidth, forKey: Self.menuBarMaxWidthKey)
        }
    }

    static let rotationIntervals: [(label: String, seconds: TimeInterval)] = [
        ("3 seconds", 3),
        ("5 seconds", 5),
        ("10 seconds", 10),
        ("15 seconds", 15),
        ("30 seconds", 30),
        ("60 seconds", 60),
    ]

    @Published var showAdsWhenLicensed: Bool {
        didSet {
            UserDefaults.standard.set(showAdsWhenLicensed, forKey: Self.showAdsKey)
        }
    }

    /// Holdings: symbol → number of shares
    @Published var holdings: [String: Double] {
        didSet {
            if let data = try? JSONEncoder().encode(holdings) {
                UserDefaults.standard.set(data, forKey: Self.holdingsKey)
            }
        }
    }

    @Published var showHoldings: Bool {
        didSet {
            UserDefaults.standard.set(showHoldings, forKey: Self.showHoldingsKey)
        }
    }

    func sharesFor(_ symbol: String) -> Double {
        holdings[symbol] ?? 0
    }

    func setShares(_ shares: Double, for symbol: String) {
        if shares <= 0 {
            holdings.removeValue(forKey: symbol)
        } else {
            holdings[symbol] = shares
        }
    }

    /// Sort order per category (keyed by category UUID string)
    @Published var categorySortOrders: [String: Int] {
        didSet {
            UserDefaults.standard.set(categorySortOrders, forKey: Self.categorySortKey)
        }
    }

    func sortOrder(for categoryId: UUID) -> CategorySortOrder {
        CategorySortOrder(rawValue: categorySortOrders[categoryId.uuidString] ?? 0) ?? .manual
    }

    func setSortOrder(_ order: CategorySortOrder, for categoryId: UUID) {
        categorySortOrders[categoryId.uuidString] = order.rawValue
    }

    @Published var analyticsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(analyticsEnabled, forKey: Self.analyticsEnabledKey)
            if !analyticsEnabled {
                AnalyticsService.shared.optOut()
            }
        }
    }

    /// All unique symbols across all items
    var allSymbols: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in items {
            for s in item.allSymbols where !seen.contains(s) {
                seen.insert(s)
                result.append(s)
            }
        }
        return result
    }

    var totalSymbolCount: Int {
        allSymbols.count
    }

    private init() {
        // Load items
        let loadedItems: [TickerItem]
        if let data = UserDefaults.standard.data(forKey: Self.itemsKey),
           let decoded = try? JSONDecoder().decode([TickerItem].self, from: data) {
            loadedItems = decoded
        } else if let legacySymbols = UserDefaults.standard.stringArray(forKey: Self.legacySymbolsKey) {
            // Migrate from old flat list
            loadedItems = legacySymbols.map { TickerItem.single($0) }
        } else {
            loadedItems = [
                .single("AAPL"),
                .single("GOOGL"),
                .category("Tech", icon: "laptopcomputer", symbols: ["MSFT", "META", "NVDA"]),
            ]
        }

        self.items = loadedItems
        self.primarySymbol = UserDefaults.standard.string(forKey: Self.primarySymbolKey) ?? loadedItems.first?.allSymbols.first ?? "AAPL"

        let storedInterval = UserDefaults.standard.double(forKey: Self.refreshIntervalKey)
        self.refreshInterval = storedInterval > 0 ? storedInterval : 60

        self.displayFormat = TickerDisplayFormat(rawValue: UserDefaults.standard.integer(forKey: Self.displayFormatKey)) ?? .tickerPriceAndChange
        self.trendStyle = TickerTrendStyle(rawValue: UserDefaults.standard.integer(forKey: Self.trendStyleKey)) ?? .arrowWithPercent
        self.colorMode = TickerColorMode(rawValue: UserDefaults.standard.integer(forKey: Self.colorModeKey)) ?? .colored
        self.detailLevel = DropdownDetailLevel(rawValue: UserDefaults.standard.integer(forKey: Self.detailLevelKey)) ?? .detailed
        self.showGraph = UserDefaults.standard.object(forKey: Self.showGraphKey) == nil ? true : UserDefaults.standard.bool(forKey: Self.showGraphKey)
        self.rotatingSymbols = UserDefaults.standard.stringArray(forKey: Self.rotatingSymbolsKey) ?? []
        self.rotationEnabled = UserDefaults.standard.bool(forKey: Self.rotationEnabledKey)
        let storedRotation = UserDefaults.standard.double(forKey: Self.rotationIntervalKey)
        self.rotationInterval = storedRotation > 0 ? storedRotation : 5
        self.rotationMode = RotationMode(rawValue: UserDefaults.standard.string(forKey: Self.rotationModeKey) ?? "") ?? .swap
        self.notificationsEnabled = UserDefaults.standard.bool(forKey: Self.notificationsEnabledKey)
        if UserDefaults.standard.object(forKey: Self.notifyOnPriceChangeKey) == nil {
            self.notifyOnPriceChangeEnabled = true
        } else {
            self.notifyOnPriceChangeEnabled = UserDefaults.standard.bool(forKey: Self.notifyOnPriceChangeKey)
        }
        let storedThreshold = UserDefaults.standard.double(forKey: Self.priceChangeThresholdKey)
        self.priceChangePercentThreshold = storedThreshold > 0 ? storedThreshold : 5.0
        self.clipboardEnabled = UserDefaults.standard.bool(forKey: Self.clipboardEnabledKey)
        let storedLimit = UserDefaults.standard.integer(forKey: Self.clipboardHistoryLimitKey)
        self.clipboardHistoryLimit = storedLimit > 0 ? storedLimit : 30
        if UserDefaults.standard.object(forKey: Self.clipboardShortcutEnabledKey) == nil {
            self.clipboardShortcutEnabled = true
        } else {
            self.clipboardShortcutEnabled = UserDefaults.standard.bool(forKey: Self.clipboardShortcutEnabledKey)
        }
        self.clipboardSyncEnabled = UserDefaults.standard.bool(forKey: Self.clipboardSyncEnabledKey)
        self.clipboardSyncKey = UserDefaults.standard.string(forKey: Self.clipboardSyncKeyKey) ?? ""
        let storedW = UserDefaults.standard.integer(forKey: Self.clipboardWindowWidthKey)
        self.clipboardWindowWidth = storedW > 0 ? storedW : 780
        let storedH = UserDefaults.standard.integer(forKey: Self.clipboardWindowHeightKey)
        self.clipboardWindowHeight = storedH > 0 ? storedH : 480
        let storedCB = UserDefaults.standard.integer(forKey: Self.clipboardShortcutKeyCodeKey)
        self.clipboardShortcutKeyCode = storedCB > 0 ? UInt32(storedCB) : 9  // V
        let storedCBM = UserDefaults.standard.integer(forKey: Self.clipboardShortcutModifiersKey)
        self.clipboardShortcutModifiers = storedCBM > 0 ? UInt32(storedCBM) : (256 | 512)  // ⌘⇧

        self.todoEnabled = UserDefaults.standard.bool(forKey: Self.todoEnabledKey)
        if UserDefaults.standard.object(forKey: Self.todoShortcutEnabledKey) == nil {
            self.todoShortcutEnabled = true
        } else {
            self.todoShortcutEnabled = UserDefaults.standard.bool(forKey: Self.todoShortcutEnabledKey)
        }
        let storedTK = UserDefaults.standard.integer(forKey: Self.todoShortcutKeyCodeKey)
        self.todoShortcutKeyCode = storedTK > 0 ? UInt32(storedTK) : 17  // T
        let storedTKM = UserDefaults.standard.integer(forKey: Self.todoShortcutModifiersKey)
        self.todoShortcutModifiers = storedTKM > 0 ? UInt32(storedTKM) : (256 | 512)  // ⌘⇧
        let storedTW = UserDefaults.standard.integer(forKey: Self.todoWindowWidthKey)
        self.todoWindowWidth = storedTW > 0 ? storedTW : 520
        let storedTH = UserDefaults.standard.integer(forKey: Self.todoWindowHeightKey)
        self.todoWindowHeight = storedTH > 0 ? storedTH : 560
        self.todoSyncEnabled = UserDefaults.standard.bool(forKey: Self.todoSyncEnabledKey)
        self.showMarketCap = UserDefaults.standard.bool(forKey: Self.showMarketCapKey)
        self.menuBarMaxWidth = UserDefaults.standard.double(forKey: Self.menuBarMaxWidthKey)
        self.showAdsWhenLicensed = UserDefaults.standard.bool(forKey: Self.showAdsKey)
        if let holdingsData = UserDefaults.standard.data(forKey: Self.holdingsKey),
           let decoded = try? JSONDecoder().decode([String: Double].self, from: holdingsData) {
            self.holdings = decoded
        } else {
            self.holdings = [:]
        }
        self.showHoldings = UserDefaults.standard.bool(forKey: Self.showHoldingsKey)
        self.categorySortOrders = (UserDefaults.standard.dictionary(forKey: Self.categorySortKey) as? [String: Int]) ?? [:]

        // Analytics defaults to enabled; users can opt out
        if UserDefaults.standard.object(forKey: Self.analyticsEnabledKey) == nil {
            self.analyticsEnabled = true
        } else {
            self.analyticsEnabled = UserDefaults.standard.bool(forKey: Self.analyticsEnabledKey)
        }
    }

    private func saveItems() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.itemsKey)
        }
    }

    // MARK: - Item management

    func addSingleTicker(_ symbol: String) -> Bool {
        let cleaned = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidSymbol(cleaned), !allSymbols.contains(cleaned) else {
            return false
        }
        items.append(.single(cleaned))
        AnalyticsService.shared.track("stock_added", properties: ["symbol": cleaned, "context": "single"])
        return true
    }

    func addCategory(name: String, icon: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(.category(trimmed, icon: icon, symbols: []))
        AnalyticsService.shared.track("category_created", properties: ["category": trimmed])
    }

    func addSymbolToCategory(itemId: UUID, symbol: String) -> Bool {
        let cleaned = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidSymbol(cleaned), !allSymbols.contains(cleaned) else {
            return false
        }
        guard let idx = items.firstIndex(where: { $0.id == itemId }),
              case .category(let name, let icon, var symbols) = items[idx].kind else {
            return false
        }
        symbols.append(cleaned)
        items[idx] = TickerItem(id: itemId, kind: .category(name: name, icon: icon, symbols: symbols))
        AnalyticsService.shared.track("stock_added", properties: ["symbol": cleaned, "context": "category", "category": name])
        return true
    }

    func removeSymbolFromCategory(itemId: UUID, symbolIndex: IndexSet) {
        guard let idx = items.firstIndex(where: { $0.id == itemId }),
              case .category(let name, let icon, var symbols) = items[idx].kind else {
            return
        }
        let removedSymbols = symbolIndex.map { symbols[$0] }
        symbols.remove(atOffsets: symbolIndex)
        items[idx] = TickerItem(id: itemId, kind: .category(name: name, icon: icon, symbols: symbols))
        for sym in removedSymbols {
            AnalyticsService.shared.track("stock_removed", properties: ["symbol": sym, "context": "category"])
        }
        if removedSymbols.contains(primarySymbol) {
            primarySymbol = allSymbols.first ?? ""
        }
    }

    func removeItem(at indices: IndexSet) {
        let removedItems = indices.map { items[$0] }
        let removedSymbols = removedItems.flatMap { $0.allSymbols }
        items.remove(atOffsets: indices)
        for item in removedItems {
            for sym in item.allSymbols {
                AnalyticsService.shared.track("stock_removed", properties: ["symbol": sym, "context": item.isCategory ? "category" : "single"])
            }
        }
        if removedSymbols.contains(primarySymbol) {
            primarySymbol = allSymbols.first ?? ""
        }
    }

    func renameCategory(itemId: UUID, newName: String) {
        guard let idx = items.firstIndex(where: { $0.id == itemId }),
              case .category(_, let icon, let symbols) = items[idx].kind else {
            return
        }
        items[idx] = TickerItem(id: itemId, kind: .category(name: newName, icon: icon, symbols: symbols))
    }

    func updateCategoryIcon(itemId: UUID, newIcon: String) {
        guard let idx = items.firstIndex(where: { $0.id == itemId }),
              case .category(let name, _, let symbols) = items[idx].kind else {
            return
        }
        items[idx] = TickerItem(id: itemId, kind: .category(name: name, icon: newIcon, symbols: symbols))
    }

    /// Move a single ticker into a category (removes it as standalone, adds to category)
    func moveTickerToCategory(symbol: String, categoryId: UUID) {
        // Remove from wherever it currently is
        removeTickerFromAll(symbol: symbol)
        // Add to target category
        guard let idx = items.firstIndex(where: { $0.id == categoryId }),
              case .category(let name, let icon, var symbols) = items[idx].kind else { return }
        symbols.append(symbol)
        items[idx] = TickerItem(id: categoryId, kind: .category(name: name, icon: icon, symbols: symbols))
    }

    /// Move a ticker out of its category to standalone
    func moveTickerToStandalone(symbol: String, fromCategoryId: UUID) {
        // Remove from category
        guard let idx = items.firstIndex(where: { $0.id == fromCategoryId }),
              case .category(let name, let icon, var symbols) = items[idx].kind,
              let symIdx = symbols.firstIndex(of: symbol) else { return }
        symbols.remove(at: symIdx)
        items[idx] = TickerItem(id: fromCategoryId, kind: .category(name: name, icon: icon, symbols: symbols))
        // Add as standalone
        items.append(.single(symbol))
    }

    private func removeTickerFromAll(symbol: String) {
        // Remove if it's a standalone single
        items.removeAll { item in
            if case .single(let s) = item.kind, s == symbol { return true }
            return false
        }
        // Remove from any category
        for i in items.indices {
            if case .category(let name, let icon, var symbols) = items[i].kind,
               let symIdx = symbols.firstIndex(of: symbol) {
                symbols.remove(at: symIdx)
                items[i] = TickerItem(id: items[i].id, kind: .category(name: name, icon: icon, symbols: symbols))
            }
        }
    }

    /// All categories for the move-to picker
    var categories: [(id: UUID, name: String)] {
        items.compactMap { item in
            if case .category(let name, _, _) = item.kind {
                return (item.id, name)
            }
            return nil
        }
    }

    func isValidSymbol(_ symbol: String) -> Bool {
        !symbol.isEmpty && symbol.count <= 10 &&
        symbol.range(of: "^[A-Z0-9.^-]+$", options: .regularExpression) != nil
    }
}

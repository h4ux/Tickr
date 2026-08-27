import Foundation
import Combine
import AppKit

/// Serial gate that enforces SEC's 10 req/s ceiling across every request
/// this app makes to data.sec.gov / sec.gov. Each `run` block is dispatched
/// on a private serial queue with a minimum spacing between successive
/// requests, so bursts of enrichment fetches are automatically throttled.
final class SECRateLimiter {
    static let shared = SECRateLimiter()
    private let queue = DispatchQueue(label: "com.tickr.app.sec.ratelimiter")
    /// 110ms → ~9 req/s. Comfortably under SEC's 10/s limit even with
    /// occasional clock drift.
    private let minInterval: TimeInterval = 0.11
    private var lastFireAt: Date = .distantPast

    private init() {}

    func run(_ block: @escaping () -> Void) {
        queue.async {
            let elapsed = Date().timeIntervalSince(self.lastFireAt)
            if elapsed < self.minInterval {
                Thread.sleep(forTimeInterval: self.minInterval - elapsed)
            }
            self.lastFireAt = Date()
            block()
        }
    }
}

/// Polls the SEC EDGAR submissions endpoint for each starred ticker that has
/// a CIK set, filters by the user's configured date range, diffs against
/// previously-seen accession numbers to detect new filings, enriches insider
/// filings (Form 3/4/5/144) with parsed owner + transaction details, and
/// optionally posts a notification when new filings appear.
///
/// SEC requires a real name/email in the `User-Agent` — the request is
/// skipped if the user hasn't set both. All outbound requests go through
/// `SECRateLimiter.shared` so we never exceed 10 req/s.
class SECService: ObservableObject {
    static let shared = SECService()

    /// Per-symbol filings (already filtered by user date range).
    @Published var filings: [String: [FilingItem]] = [:]
    @Published var isPolling = false
    @Published var lastPolledAt: Date?
    @Published var lastError: String?

    private let settings = AppSettings.shared
    private var cancellables = Set<AnyCancellable>()
    private var pollTimer: Timer?

    /// Symbol → set of accession numbers we've already seen. Used to
    /// distinguish "new filing" from "we've shown this before".
    private var seenAccessions: [String: Set<String>] = [:]

    /// Cache of parsed insider details, keyed by accession number. Prevents
    /// re-fetching the same XML on subsequent polls.
    private var insiderCache: [String: FilingItem.InsiderInfo] = [:]

    private static let persistedFilingsKey = "secFilingsCache"
    private static let seenAccessionsKey   = "secSeenAccessions"
    private static let insiderCacheKey     = "secInsiderCache"
    private static let insiderCacheVersionKey = "secInsiderCacheVersion"
    /// Bump this constant whenever the insider XML parsing changes shape —
    /// old cached results (potentially with garbled fields) get discarded on
    /// launch and the next poll re-enriches from scratch.
    private static let insiderCacheVersion  = 2

    private init() {
        loadFromDisk()

        Publishers.CombineLatest3(
            settings.$secPollingEnabled,
            settings.$secPollingIntervalMinutes,
            settings.$secSymbolCIKMap
        )
        .receive(on: RunLoop.main)
        .dropFirst()
        .sink { [weak self] _, _, _ in
            self?.restartTimer()
        }
        .store(in: &cancellables)

        restartTimer()
    }

    // MARK: - Timer

    private func restartTimer() {
        pollTimer?.invalidate()
        pollTimer = nil
        guard settings.secPollingEnabled, settings.secUserAgentConfigured else { return }

        let seconds = max(60.0, Double(settings.secPollingIntervalMinutes) * 60.0)
        let t = Timer(timeInterval: seconds, repeats: true) { [weak self] _ in
            self?.pollAll()
        }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t

        DispatchQueue.main.async { [weak self] in self?.pollAll() }
    }

    // MARK: - Public actions

    func pollAll() {
        guard settings.secUserAgentConfigured else {
            DispatchQueue.main.async {
                self.lastError = "Set your name and email under SEC settings first."
            }
            return
        }
        let map = settings.secSymbolCIKMap
        guard !map.isEmpty else { return }
        DispatchQueue.main.async { self.isPolling = true }
        let group = DispatchGroup()
        for (symbol, cik) in map {
            group.enter()
            fetch(symbol: symbol, cik: cik) { _ in group.leave() }
        }
        group.notify(queue: .main) { [weak self] in
            self?.isPolling = false
            self?.lastPolledAt = Date()
        }
    }

    func pollOne(symbol: String) {
        guard let cik = settings.cik(for: symbol) else { return }
        fetch(symbol: symbol, cik: cik) { _ in }
    }

    func markSeen(symbol: String) {
        let currentAccessions = Set(filings[symbol]?.map(\.accessionNumber) ?? [])
        seenAccessions[symbol] = currentAccessions
        saveSeenAccessions()
    }

    /// All known insider filings across all tickers, most-recent first.
    /// Used by the "Recent insider activity" section in the popover.
    var recentInsiderFilings: [FilingItem] {
        filings.values.flatMap { $0 }
            .filter { $0.isInsiderForm && $0.insider != nil }
            .sorted { $0.filingDate > $1.filingDate }
    }

    // MARK: - Networking (submissions.json)

    private func fetch(symbol: String, cik: String, completion: @escaping (Bool) -> Void) {
        let padded = padCIK(cik)
        guard let url = URL(string: "https://data.sec.gov/submissions/CIK\(padded).json") else {
            completion(false); return
        }
        var request = URLRequest(url: url)
        request.setValue(userAgentHeader, forHTTPHeaderField: "User-Agent")
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20

        SECRateLimiter.shared.run { [weak self] in
            URLSession.shared.dataTask(with: request) { data, response, error in
                guard let self = self else { completion(false); return }
                if let error = error {
                    DispatchQueue.main.async {
                        self.lastError = "SEC fetch \(symbol): \(error.localizedDescription)"
                        completion(false)
                    }
                    return
                }
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let filingsRoot = json["filings"] as? [String: Any],
                      let recent = filingsRoot["recent"] as? [String: Any],
                      let forms      = recent["form"]            as? [String],
                      let dates      = recent["filingDate"]      as? [String],
                      let accessions = recent["accessionNumber"] as? [String],
                      let documents  = recent["primaryDocument"] as? [String] else {
                    DispatchQueue.main.async {
                        self.lastError = "SEC fetch \(symbol): unexpected response"
                        completion(false)
                    }
                    return
                }
                let descriptions = recent["primaryDocDescription"] as? [String] ?? []
                let itemsArr     = recent["items"]                 as? [String] ?? []

                // Store everything SEC returns — the date-range setting only
                // filters what shows in the per-ticker view, not what we keep.
                let count = min(forms.count, dates.count, accessions.count, documents.count)
                var parsed: [FilingItem] = []
                for i in 0..<count {
                    var item = FilingItem(
                        symbol: symbol,
                        cik: padded,
                        form: forms[i],
                        filingDate: dates[i],
                        accessionNumber: accessions[i],
                        primaryDocument: documents[i],
                        title: i < descriptions.count ? descriptions[i] : "",
                        items: i < itemsArr.count ? itemsArr[i] : ""
                    )
                    if let cached = self.insiderCache[item.accessionNumber] {
                        item.insider = cached
                    }
                    parsed.append(item)
                }
                parsed.sort { $0.filingDate > $1.filingDate }

                DispatchQueue.main.async {
                    self.applyFilings(parsed, symbol: symbol)
                    self.lastError = nil
                    completion(true)
                    // Kick off insider XML enrichment for any newly-added
                    // insider filings that we don't have cached yet.
                    self.enrichInsiderFilings(for: symbol)
                }
            }.resume()
        }
    }

    /// Merge freshly-fetched filings into whatever we already had for the
    /// symbol. We never discard old entries — only add or update in place —
    /// so the SEC Filings tab accumulates a complete pull history over time,
    /// even for filings that have since aged out of the user's date-range
    /// display setting.
    private func applyFilings(_ items: [FilingItem], symbol: String) {
        let existing = filings[symbol] ?? []
        var byAccession: [String: FilingItem] =
            Dictionary(uniqueKeysWithValues: existing.map { ($0.accessionNumber, $0) })

        for var item in items {
            // If we've previously enriched this filing with insider data
            // but this pull returned it without insider, keep the older data.
            if item.insider == nil, let prior = byAccession[item.accessionNumber]?.insider {
                item.insider = prior
            }
            byAccession[item.accessionNumber] = item
        }

        let merged = Array(byAccession.values).sorted { $0.filingDate > $1.filingDate }

        // "New" for notifications = items in this pull that we hadn't seen before.
        let prevSeen = seenAccessions[symbol] ?? []
        let newOnes = items.filter { !prevSeen.contains($0.accessionNumber) }

        filings[symbol] = merged

        let hadPriorState = seenAccessions[symbol] != nil
        if hadPriorState, !newOnes.isEmpty, settings.secNotifyOnNewFilings {
            NotificationService.shared.sendSECFilings(symbol: symbol, newFilings: newOnes)
        }

        // Record every accession we've ever seen (including historical
        // merged entries) so we never mistakenly re-notify for them later.
        seenAccessions[symbol] = Set(merged.map(\.accessionNumber))
        saveFilings()
        saveSeenAccessions()
    }

    /// Filings within the user's configured date-range window — used by
    /// the per-ticker expanded row so it doesn't overflow with old items.
    /// The SEC Filings tab shows the full unfiltered set via `filings`.
    func recentFilings(for symbol: String) -> [FilingItem] {
        let cutoff = cutoffDateString()
        return (filings[symbol] ?? []).filter { $0.filingDate >= cutoff }
    }

    // MARK: - Networking (insider XML enrichment)

    private func enrichInsiderFilings(for symbol: String) {
        guard let items = filings[symbol] else { return }
        for item in items where item.isInsiderForm && item.insider == nil {
            fetchInsiderXML(for: item)
        }
    }

    private func fetchInsiderXML(for filing: FilingItem) {
        guard let xmlURL = insiderXMLURL(for: filing) else { return }
        var request = URLRequest(url: xmlURL)
        request.setValue(userAgentHeader, forHTTPHeaderField: "User-Agent")
        request.setValue("gzip, deflate", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20

        SECRateLimiter.shared.run { [weak self] in
            URLSession.shared.dataTask(with: request) { data, response, _ in
                guard let self = self,
                      let data = data,
                      let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      let xml = String(data: data, encoding: .utf8) else { return }

                guard let parsed = self.parseInsiderXML(xml) else { return }
                DispatchQueue.main.async {
                    self.insiderCache[filing.accessionNumber] = parsed
                    // Splice the parsed insider info back into the published
                    // filings so any observing view re-renders immediately.
                    if var arr = self.filings[filing.symbol] {
                        for (idx, existing) in arr.enumerated()
                        where existing.accessionNumber == filing.accessionNumber {
                            arr[idx].insider = parsed
                        }
                        self.filings[filing.symbol] = arr
                    }
                    self.saveFilings()
                    self.saveInsiderCache()
                }
            }.resume()
        }
    }

    /// SEC hosts Form 3/4/5 XMLs at `<accessionNoDashes>/form<n>.xml` and
    /// Form 144 at `<accessionNoDashes>/primary_doc.xml` in older filings.
    /// We try the form-specific name first, fall back to primary_doc.xml.
    private func insiderXMLURL(for filing: FilingItem) -> URL? {
        let accNoDashes = filing.accessionNumber.replacingOccurrences(of: "-", with: "")
        let cikNumeric = filing.cik.trimmingCharacters(in: CharacterSet(charactersIn: "0"))
        let numeric = cikNumeric.isEmpty ? filing.cik : cikNumeric
        let baseForm = filing.form.replacingOccurrences(of: "/A", with: "")

        let filename: String
        switch baseForm {
        case "3":   filename = "form3.xml"
        case "4":   filename = "form4.xml"
        case "5":   filename = "form5.xml"
        case "144": filename = "primary_doc.xml"
        default:    filename = "primary_doc.xml"
        }
        return URL(string: "https://www.sec.gov/Archives/edgar/data/\(numeric)/\(accNoDashes)/\(filename)")
    }

    /// Extract the Form-4-ish fields we care about from a filing's XML.
    /// Uses regex rather than XMLParser to keep the code compact — the tag
    /// names we look at are unambiguous within the ownership schema.
    private func parseInsiderXML(_ xml: String) -> FilingItem.InsiderInfo? {
        func first(_ tag: String) -> String? {
            let pattern = "<\(tag)>\\s*([^<]+?)\\s*</\(tag)>"
            if let range = xml.range(of: pattern, options: .regularExpression) {
                let match = String(xml[range])
                let inner = match
                    .replacingOccurrences(of: "<\(tag)>", with: "")
                    .replacingOccurrences(of: "</\(tag)>", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return inner.isEmpty ? nil : inner
            }
            return nil
        }
        /// Ownership schema wraps most numeric leaves in `<value>...</value>`
        /// inside a parent tag — grab that inner value using the regex
        /// capture group so we return only the actual number, not the tags.
        func firstValue(inside parent: String, from block: String) -> String? {
            let pattern = "<\(parent)>\\s*<value>\\s*([^<]+?)\\s*</value>"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
                  let match = regex.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: block) else { return nil }
            let inner = String(block[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            return inner.isEmpty ? nil : inner
        }
        func plainValue(inside parent: String, from block: String) -> String? {
            // Some fields are `<parent>value</parent>` without a nested <value>.
            let pattern = "<\(parent)>\\s*([^<]+?)\\s*</\(parent)>"
            guard let match = block.range(of: pattern, options: .regularExpression) else { return nil }
            let sub = String(block[match])
            let inner = sub.replacingOccurrences(of: "<\(parent)>", with: "")
                .replacingOccurrences(of: "</\(parent)>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return inner.isEmpty ? nil : inner
        }

        let ownerName = first("rptOwnerName") ?? first("filerFullName") ?? ""
        guard !ownerName.isEmpty else { return nil }

        let ownerCik = first("rptOwnerCik") ?? first("filerCik") ?? ""
        let period = first("periodOfReport") ?? ""

        var relationships: [String] = []
        if first("isDirector") == "1" { relationships.append("Director") }
        if first("isOfficer") == "1" {
            let title = first("officerTitle") ?? ""
            relationships.append(title.isEmpty ? "Officer" : "Officer — \(title)")
        }
        if first("isTenPercentOwner") == "1" { relationships.append("10%+ Owner") }
        if first("isOther") == "1" {
            let other = first("otherText") ?? "Other"
            relationships.append(other)
        }

        // Parse each transaction block — both non-derivative (regular shares)
        // and derivative (options/warrants).
        var transactions: [FilingItem.InsiderTransaction] = []
        for (parentTag, isDeriv) in [("nonDerivativeTransaction", false),
                                     ("derivativeTransaction",    true)] {
            let openTag = "<\(parentTag)>"
            let closeTag = "</\(parentTag)>"
            var searchRange = xml.startIndex..<xml.endIndex
            while let open = xml.range(of: openTag, range: searchRange),
                  let close = xml.range(of: closeTag, range: open.upperBound..<xml.endIndex) {
                let block = String(xml[open.upperBound..<close.lowerBound])
                searchRange = close.upperBound..<xml.endIndex

                let security = plainValue(inside: "securityTitle", from: block)
                    ?? firstValue(inside: "securityTitle", from: block)
                    ?? "Common Stock"
                let date       = firstValue(inside: "transactionDate", from: block) ?? ""
                let code       = firstValue(inside: "transactionCode", from: block)
                    ?? plainValue(inside: "transactionCode", from: block)
                    ?? ""
                let ad         = firstValue(inside: "transactionAcquiredDisposedCode", from: block)
                    ?? plainValue(inside: "transactionAcquiredDisposedCode", from: block)
                    ?? ""
                let shares     = firstValue(inside: "transactionShares", from: block) ?? ""
                let price      = firstValue(inside: "transactionPricePerShare", from: block)
                let held       = firstValue(inside: "sharesOwnedFollowingTransaction", from: block) ?? ""
                let ownership  = firstValue(inside: "directOrIndirectOwnership", from: block)
                    ?? plainValue(inside: "directOrIndirectOwnership", from: block)
                    ?? ""
                let nature     = firstValue(inside: "natureOfOwnership", from: block)

                transactions.append(FilingItem.InsiderTransaction(
                    securityTitle: security,
                    date: date,
                    code: code,
                    acquiredDisposed: ad,
                    shares: shares,
                    price: price,
                    sharesHeldAfter: held,
                    directOrIndirect: ownership,
                    ownershipNature: nature,
                    isDerivative: isDeriv
                ))
            }
        }

        return FilingItem.InsiderInfo(
            ownerName: ownerName,
            ownerCIK: ownerCik,
            relationships: relationships,
            periodOfReport: period,
            transactions: transactions
        )
    }

    // MARK: - Helpers

    private var userAgentHeader: String {
        "\(settings.secUserAgentName) \(settings.secUserAgentEmail)"
    }

    private func padCIK(_ cik: String) -> String {
        var digits = cik.uppercased()
        if digits.hasPrefix("CIK") { digits.removeFirst(3) }
        digits = digits.filter(\.isNumber)
        if digits.count >= 10 { return String(digits.suffix(10)) }
        return String(repeating: "0", count: 10 - digits.count) + digits
    }

    private func cutoffDateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let cutoff = Calendar.current.date(byAdding: .day, value: -max(1, settings.secDateRangeDays), to: Date()) ?? Date()
        return f.string(from: cutoff)
    }

    // MARK: - Backup

    /// Everything this service persists, for the backup exporter.
    func exportSnapshot() -> (filings: [String: [FilingItem]],
                              seenAccessions: [String: [String]],
                              insiderCache: [String: FilingItem.InsiderInfo]) {
        (filings, seenAccessions.mapValues { Array($0) }, insiderCache)
    }

    /// Replace the cached filings wholesale (used by backup import).
    func importSnapshot(filings: [String: [FilingItem]],
                        seenAccessions: [String: Set<String>],
                        insiderCache: [String: FilingItem.InsiderInfo]) {
        self.filings = filings
        self.seenAccessions = seenAccessions
        self.insiderCache = insiderCache
        saveFilings()
        saveSeenAccessions()
        saveInsiderCache()
        UserDefaults.standard.set(Self.insiderCacheVersion, forKey: Self.insiderCacheVersionKey)
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        if let data = UserDefaults.standard.data(forKey: Self.persistedFilingsKey),
           let decoded = try? JSONDecoder().decode([String: [FilingItem]].self, from: data) {
            filings = decoded
        }
        if let data = UserDefaults.standard.data(forKey: Self.seenAccessionsKey),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            seenAccessions = decoded.mapValues { Set($0) }
        }

        // Discard the insider cache if it was written by an older parser
        // version — otherwise garbled tag fragments (e.g. "38915</value>")
        // stick around. Also wipe the insider field on cached filings so
        // enrichment re-runs cleanly.
        let cachedVersion = UserDefaults.standard.integer(forKey: Self.insiderCacheVersionKey)
        if cachedVersion == Self.insiderCacheVersion,
           let data = UserDefaults.standard.data(forKey: Self.insiderCacheKey),
           let decoded = try? JSONDecoder().decode([String: FilingItem.InsiderInfo].self, from: data) {
            insiderCache = decoded
        } else {
            insiderCache = [:]
            for (symbol, items) in filings {
                filings[symbol] = items.map { item in
                    var copy = item
                    copy.insider = nil
                    return copy
                }
            }
            UserDefaults.standard.removeObject(forKey: Self.insiderCacheKey)
            UserDefaults.standard.set(Self.insiderCacheVersion, forKey: Self.insiderCacheVersionKey)
        }
    }

    private func saveFilings() {
        if let data = try? JSONEncoder().encode(filings) {
            UserDefaults.standard.set(data, forKey: Self.persistedFilingsKey)
        }
    }

    private func saveSeenAccessions() {
        let plain = seenAccessions.mapValues { Array($0) }
        if let data = try? JSONEncoder().encode(plain) {
            UserDefaults.standard.set(data, forKey: Self.seenAccessionsKey)
        }
    }

    private func saveInsiderCache() {
        if let data = try? JSONEncoder().encode(insiderCache) {
            UserDefaults.standard.set(data, forKey: Self.insiderCacheKey)
        }
    }
}

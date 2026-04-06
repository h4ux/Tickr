import Foundation
import Combine

class StockService: ObservableObject {
    static let shared = StockService()

    @Published var quotes: [StockQuote] = []
    @Published var lastUpdated: Date?
    @Published var errorMessage: String?
    @Published var isLoading = false

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private let settings = AppSettings.shared
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)

        settings.$refreshInterval
            .sink { [weak self] _ in self?.restartTimer() }
            .store(in: &cancellables)

        settings.$items
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.fetchQuotes()
                self?.restartTimer()
            }
            .store(in: &cancellables)
    }

    func startFetching() {
        fetchQuotes()
        restartTimer()
    }

    func stopFetching() {
        timer?.invalidate()
        timer = nil
    }

    private func restartTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.timer?.invalidate()
            let t = Timer(timeInterval: self.settings.refreshInterval, repeats: true) { [weak self] _ in
                self?.fetchQuotes()
            }
            RunLoop.main.add(t, forMode: .common)
            self.timer = t
        }
    }

    func fetchQuotes() {
        let symbols = settings.allSymbols
        guard !symbols.isEmpty else {
            DispatchQueue.main.async {
                self.quotes = []
                self.errorMessage = nil
            }
            return
        }

        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }

        let group = DispatchGroup()
        var fetchedQuotes: [String: StockQuote] = [:]
        let lock = NSLock()
        var fetchErrors: [String] = []

        for symbol in symbols {
            group.enter()
            fetchSingleQuote(symbol: symbol) { result in
                defer { group.leave() }
                switch result {
                case .success(let quote):
                    lock.lock()
                    fetchedQuotes[symbol] = quote
                    lock.unlock()
                case .failure(let error):
                    lock.lock()
                    fetchErrors.append("\(symbol): \(error.localizedDescription)")
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isLoading = false

            if fetchedQuotes.isEmpty && !fetchErrors.isEmpty {
                self.errorMessage = "Failed to fetch quotes"
            } else {
                self.quotes = symbols.compactMap { fetchedQuotes[$0] }
                self.lastUpdated = Date()
                self.errorMessage = nil
            }
        }
    }

    // Caches (sector/industry/market cap don't change often)
    private var sectorCache: [String: (sector: String?, industry: String?)] = [:]
    private var marketCapCache: [String: String] = [:]

    private func fetchSingleQuote(symbol: String, completion: @escaping (Result<StockQuote, Error>) -> Void) {
        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=1d&range=2d") else {
            completion(.failure(NSError(domain: "Tickr", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid symbol"])))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(NSError(domain: "Tickr", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data"])))
                return
            }

            do {
                let decoded = try JSONDecoder().decode(YahooChartResponse.self, from: data)

                if let chartError = decoded.chart.error {
                    completion(.failure(NSError(domain: "Tickr", code: -3, userInfo: [NSLocalizedDescriptionKey: chartError.description ?? "API error"])))
                    return
                }

                guard let result = decoded.chart.result?.first else {
                    completion(.failure(NSError(domain: "Tickr", code: -4, userInfo: [NSLocalizedDescriptionKey: "No results"])))
                    return
                }

                let meta = result.meta
                let price = meta.regularMarketPrice ?? 0
                let previousClose = meta.chartPreviousClose ?? price
                let change = price - previousClose
                let changePercent = previousClose != 0 ? (change / previousClose) * 100 : 0
                let exchange = meta.fullExchangeName ?? meta.exchangeName ?? ""


                // Return quote immediately with cached enrichment data
                // Enrichment fetches in background — will be available on next refresh
                let cachedSector = self?.sectorCache[symbol]
                let cachedMCap = self?.marketCapCache[symbol]

                let quote = StockQuote(
                    symbol: meta.symbol,
                    companyName: meta.longName ?? meta.shortName ?? meta.symbol,
                    price: price,
                    change: change,
                    changePercent: changePercent,
                    previousClose: previousClose,
                    dayHigh: meta.regularMarketDayHigh,
                    dayLow: meta.regularMarketDayLow,
                    volume: meta.regularMarketVolume,
                    fiftyTwoWeekHigh: meta.fiftyTwoWeekHigh,
                    fiftyTwoWeekLow: meta.fiftyTwoWeekLow,
                    currency: meta.currency ?? "USD",
                    exchange: exchange,
                    sector: cachedSector?.sector,
                    industry: cachedSector?.industry,
                    marketCap: cachedMCap
                )
                completion(.success(quote))

                // Fetch enrichment in background (cached for next refresh)
                if cachedSector == nil {
                    self?.fetchSectorInfo(symbol: symbol) { _, _ in }
                }
                if cachedMCap == nil {
                    self?.fetchMarketCap(symbol: symbol, exchange: exchange) { _ in }
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func fetchSectorInfo(symbol: String, completion: @escaping (String?, String?) -> Void) {
        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://query2.finance.yahoo.com/v1/finance/search?q=\(encoded)&quotesCount=1&newsCount=0") else {
            completion(nil, nil); return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { [weak self] data, _, _ in
            guard let data = data,
                  let decoded = try? JSONDecoder().decode(YahooSearchResponse.self, from: data),
                  let match = decoded.quotes?.first(where: { $0.symbol == symbol }) else {
                completion(nil, nil); return
            }

            let sector = match.sectorDisp ?? match.sector
            let industry = match.industryDisp ?? match.industry
            self?.sectorCache[symbol] = (sector, industry)
            completion(sector, industry)
        }.resume()
    }

    // Lazy Google Finance session with consent cookie
    private lazy var googleSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = 15
        // Set Google consent cookie to bypass consent wall
        if let cookie = HTTPCookie(properties: [
            .domain: ".google.com", .path: "/", .name: "SOCS",
            .value: "CAISHAgBEhJnd3NfMjAyNDAxMDEtMF9SQzIaAmVuIAEaBgiA_LmuBg",
            .secure: "TRUE",
        ]) {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
        return URLSession(configuration: config)
    }()

    private func fetchMarketCap(symbol: String, exchange: String, completion: @escaping (String?) -> Void) {
        let exchangeMap: [String: String] = [
            "NMS": "NASDAQ", "NGM": "NASDAQ", "NCM": "NASDAQ", "NasdaqGS": "NASDAQ",
            "NasdaqGM": "NASDAQ", "NasdaqCM": "NASDAQ",
            "NYQ": "NYSE", "New York Stock Exchange": "NYSE", "NYSE": "NYSE",
            "PCX": "NYSEARCA", "BTS": "NYSEARCA", "NYSEArca": "NYSEARCA",
            "LSE": "LON", "London Stock Exchange": "LON",
            "TYO": "TYO", "Tokyo": "TYO",
        ]
        let gExchange = exchangeMap[exchange] ?? "NASDAQ"

        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/finance/quote/\(encoded):\(gExchange)") else {
            completion(nil); return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        googleSession.dataTask(with: request) { [weak self] data, _, _ in
            guard let data = data, let html = String(data: data, encoding: .utf8) else {
                completion(nil); return
            }

            guard let mcIdx = html.range(of: "Market cap") else {
                completion(nil); return
            }
            let afterMC = html[mcIdx.upperBound...]

            if let divStart = afterMC.range(of: "P6K39c\">"),
               let divEnd = afterMC[divStart.upperBound...].range(of: "<") {
                var raw = String(afterMC[divStart.upperBound..<divEnd.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let spaceIdx = raw.lastIndex(of: " "), raw[spaceIdx...].count <= 5 {
                    raw = String(raw[..<spaceIdx])
                }
                if !raw.isEmpty && raw.count < 20 {
                    self?.marketCapCache[symbol] = raw
                    completion(raw)
                    return
                }
            }
            completion(nil)
        }.resume()
    }

    // MARK: - News & Earnings

    @Published var newsItems: [StockNewsItem] = []
    @Published var earningsDate: String?
    @Published var newsLoading = false
    @Published var newsSymbol: String = ""
    private var newsCache: [String: [StockNewsItem]] = [:]
    private var earningsCache: [String: String] = [:]

    func fetchNews(for symbol: String) {
        newsSymbol = symbol

        // Load from cache instantly
        if let cachedNews = newsCache[symbol] {
            DispatchQueue.main.async { self.newsItems = cachedNews }
        }
        if let cachedEarnings = earningsCache[symbol] {
            DispatchQueue.main.async { self.earningsDate = cachedEarnings }
        }

        // If both cached, skip network
        if newsCache[symbol] != nil && earningsCache[symbol] != nil { return }

        DispatchQueue.main.async {
            self.newsLoading = true
            if self.newsCache[symbol] == nil { self.newsItems = [] }
            if self.earningsCache[symbol] == nil { self.earningsDate = nil }
        }

        let group = DispatchGroup()

        // Fetch news from Yahoo
        if newsCache[symbol] == nil {
            group.enter()
            fetchNewsFromYahoo(symbol: symbol) { [weak self] items in
                DispatchQueue.main.async { self?.newsItems = items }
                self?.newsCache[symbol] = items
                group.leave()
            }
        }

        // Fetch earnings date from EarningsWhispers
        if earningsCache[symbol] == nil {
            group.enter()
            fetchEarningsDate(symbol: symbol) { [weak self] date in
                DispatchQueue.main.async { self?.earningsDate = date }
                if let date = date { self?.earningsCache[symbol] = date }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.newsLoading = false
        }
    }

    private func fetchNewsFromYahoo(symbol: String, completion: @escaping ([StockNewsItem]) -> Void) {
        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://query2.finance.yahoo.com/v1/finance/search?q=\(encoded)&quotesCount=0&newsCount=5") else {
            completion([]); return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { data, _, _ in
            var items: [StockNewsItem] = []
            if let data = data,
               let decoded = try? JSONDecoder().decode(YahooSearchResponse.self, from: data),
               let news = decoded.news {
                items = news.compactMap { n in
                    guard let title = n.title, let link = n.link else { return nil }
                    return StockNewsItem(title: title, link: link, publisher: n.publisher ?? "")
                }
            }
            completion(items)
        }.resume()
    }

    private func fetchEarningsDate(symbol: String, completion: @escaping (String?) -> Void) {
        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.earningswhispers.com/stocks/\(encoded)") else {
            completion(nil); return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { data, _, _ in
            guard let data = data, let html = String(data: data, encoding: .utf8) else {
                completion(nil); return
            }
            // Pattern: "report earnings on Thursday, April 30, 2026"
            let pattern = "report earnings on \\w+day,\\s*(\\w+ \\d{1,2},?\\s*\\d{4})"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else {
                completion(nil); return
            }

            let dateStr = String(html[range])

            // Parse the date and check if it's in the future
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "MMMM d, yyyy"
            // Also try without comma: "MMMM d yyyy"
            if let date = formatter.date(from: dateStr) ?? {
                formatter.dateFormat = "MMMM d yyyy"
                return formatter.date(from: dateStr)
            }() {
                if date >= Calendar.current.startOfDay(for: Date()) {
                    completion(dateStr)
                } else {
                    // Past date — return TBA
                    completion("TBA")
                }
            } else {
                completion(dateStr) // Couldn't parse, show as-is
            }
        }.resume()
    }

    // MARK: - Chart data for different ranges

    @Published var chartData: [Double] = []
    @Published var chartLoading = false
    private var chartCache: [String: [Double]] = [:]

    func fetchChartData(symbol: String, range: ChartRange) {
        let cacheKey = "\(symbol)_\(range.rawValue)"
        if let cached = chartCache[cacheKey] {
            DispatchQueue.main.async { self.chartData = cached }
            return
        }

        DispatchQueue.main.async { self.chartLoading = true }

        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(encoded)?interval=\(range.interval)&range=\(range.rawValue)") else {
            DispatchQueue.main.async { self.chartLoading = false }
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { [weak self] data, _, _ in
            var prices: [Double] = []
            if let data = data,
               let decoded = try? JSONDecoder().decode(YahooChartResponse.self, from: data),
               let result = decoded.chart.result?.first,
               let closes = result.indicators?.quote?.first?.close {
                prices = closes.compactMap { $0 }
            }
            DispatchQueue.main.async {
                self?.chartData = prices
                self?.chartLoading = false
                if !prices.isEmpty { self?.chartCache[cacheKey] = prices }
            }
        }.resume()
    }

    // MARK: - Lookups

    var primaryQuote: StockQuote? {
        let symbol = settings.primarySymbol
        return quotes.first { $0.symbol == symbol }
    }

    func quote(for symbol: String) -> StockQuote? {
        quotes.first { $0.symbol == symbol }
    }

    /// Sort symbols within a category based on sort order
    func sortedSymbols(_ symbols: [String], by order: CategorySortOrder) -> [String] {
        guard order != .manual else { return symbols }
        return symbols.sorted { a, b in
            let qa = quote(for: a)
            let qb = quote(for: b)
            switch order {
            case .manual:     return false
            case .nameAsc:    return a < b
            case .nameDesc:   return a > b
            case .changeDesc: return (qa?.changePercent ?? 0) > (qb?.changePercent ?? 0)
            case .changeAsc:  return (qa?.changePercent ?? 0) < (qb?.changePercent ?? 0)
            case .priceDesc:  return (qa?.price ?? 0) > (qb?.price ?? 0)
            case .priceAsc:   return (qa?.price ?? 0) < (qb?.price ?? 0)
            }
        }
    }
}

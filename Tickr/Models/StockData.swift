import Foundation

struct StockQuote: Identifiable {
    let id = UUID()
    let symbol: String
    let companyName: String
    let price: Double
    let change: Double
    let changePercent: Double
    let previousClose: Double
    let dayHigh: Double?
    let dayLow: Double?
    let volume: Int?
    let fiftyTwoWeekHigh: Double?
    let fiftyTwoWeekLow: Double?
    let currency: String
    let exchange: String
    let sector: String?
    let industry: String?
    let marketCap: String?

    var isUp: Bool { change >= 0 }

    var formattedPrice: String {
        String(format: "$%.2f", price)
    }

    var formattedChange: String {
        let sign = change >= 0 ? "+" : ""
        return String(format: "%@%.2f (%.2f%%)", sign, change, changePercent)
    }

    var formattedDayRange: String? {
        guard let low = dayLow, let high = dayHigh else { return nil }
        return String(format: "$%.2f – $%.2f", low, high)
    }

    var formatted52WeekRange: String? {
        guard let low = fiftyTwoWeekLow, let high = fiftyTwoWeekHigh else { return nil }
        return String(format: "$%.2f – $%.2f", low, high)
    }

    var formattedVolume: String? {
        guard let vol = volume else { return nil }
        if vol >= 1_000_000_000 { return String(format: "%.2fB", Double(vol) / 1_000_000_000) }
        if vol >= 1_000_000 { return String(format: "%.2fM", Double(vol) / 1_000_000) }
        if vol >= 1_000 { return String(format: "%.1fK", Double(vol) / 1_000) }
        return "\(vol)"
    }

    /// How far current price is from 52-week range (0 = at low, 1 = at high)
    var fiftyTwoWeekPosition: Double? {
        guard let low = fiftyTwoWeekLow, let high = fiftyTwoWeekHigh, high > low else { return nil }
        return (price - low) / (high - low)
    }

    var yahooFinanceURL: URL? {
        URL(string: "https://finance.yahoo.com/quote/\(symbol)")
    }

    var shortCompanyName: String {
        var name = companyName
        for suffix in [" Inc.", " Inc", " Corp.", " Corp", " Ltd.", " Ltd",
                       " Corporation", " Holdings", " Group", " Co.", " PLC", " plc",
                       " NV", " SA", " SE", ", Inc.", ", Inc"] {
            if name.hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count))
                break
            }
        }
        return name
    }

    func menuBarText(format: TickerDisplayFormat, trend: TickerTrendStyle) -> String {
        var parts: [String] = []

        switch format {
        case .priceOnly:
            break
        case .tickerAndPrice, .tickerPriceAndChange:
            parts.append(symbol)
        case .companyAndPrice, .companyPriceAndChange:
            parts.append(shortCompanyName)
        }

        parts.append(formattedPrice)

        let showTrend: Bool
        switch format {
        case .tickerPriceAndChange, .companyPriceAndChange:
            showTrend = true
        default:
            showTrend = false
        }

        if showTrend {
            switch trend {
            case .none:
                break
            case .arrow:
                parts.append(isUp ? "▲" : "▼")
            case .arrowWithPercent:
                let arrow = isUp ? "▲" : "▼"
                parts.append("\(arrow) \(String(format: "%.2f%%", abs(changePercent)))")
            case .percentOnly:
                let sign = isUp ? "+" : "-"
                parts.append("\(sign)\(String(format: "%.2f%%", abs(changePercent)))")
            }
        }

        return parts.joined(separator: " ")
    }
}

// Yahoo Finance v8 chart API response
struct YahooChartResponse: Decodable {
    let chart: Chart

    struct Chart: Decodable {
        let result: [ChartResult]?
        let error: ChartError?
    }

    struct ChartError: Decodable {
        let code: String?
        let description: String?
    }

    struct ChartResult: Decodable {
        let meta: Meta
        let indicators: Indicators?
    }

    struct Indicators: Decodable {
        let quote: [QuoteIndicator]?
    }

    struct QuoteIndicator: Decodable {
        let close: [Double?]?
    }

    struct Meta: Decodable {
        let symbol: String
        let currency: String?
        let exchangeName: String?
        let fullExchangeName: String?
        let regularMarketPrice: Double?
        let chartPreviousClose: Double?
        let regularMarketDayHigh: Double?
        let regularMarketDayLow: Double?
        let regularMarketVolume: Int?
        let fiftyTwoWeekHigh: Double?
        let fiftyTwoWeekLow: Double?
        let longName: String?
        let shortName: String?
    }
}

// News item
struct StockNewsItem: Identifiable {
    let id = UUID()
    let title: String
    let link: String
    let publisher: String
}

// Yahoo Finance search API response (for sector/industry + news)
struct YahooSearchResponse: Decodable {
    let quotes: [SearchQuote]?
    let news: [SearchNews]?

    struct SearchQuote: Decodable {
        let symbol: String?
        let sector: String?
        let sectorDisp: String?
        let industry: String?
        let industryDisp: String?
    }

    struct SearchNews: Decodable {
        let title: String?
        let link: String?
        let publisher: String?
    }
}

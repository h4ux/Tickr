import SwiftUI

struct TickerDropdownView: View {
    @ObservedObject private var stockService = StockService.shared
    @ObservedObject private var settings = AppSettings.shared
    var onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Tickr")
                    .font(.headline)
                Spacer()
                if stockService.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                }
                Button(action: { stockService.fetchQuotes() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("Refresh quotes")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Portfolio total
            if settings.showHoldings && !settings.holdings.isEmpty {
                let totalValue = settings.holdings.reduce(0.0) { total, entry in
                    let price = stockService.quote(for: entry.key)?.price ?? 0
                    return total + price * entry.value
                }
                let totalDayPL = settings.holdings.reduce(0.0) { total, entry in
                    let change = stockService.quote(for: entry.key)?.change ?? 0
                    return total + change * entry.value
                }
                if totalValue > 0 {
                    HStack {
                        Text("Portfolio")
                            .font(.system(.caption, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "$%.2f", totalValue))
                            .font(.system(.caption, design: .monospaced, weight: .bold))
                            .foregroundColor(.primary)
                        Text(String(format: "%@$%.2f", totalDayPL >= 0 ? "+" : "", totalDayPL))
                            .font(.system(.caption2, design: .monospaced, weight: .medium))
                            .foregroundColor(totalDayPL >= 0 ? Color(nsColor: .systemGreen) : Color(nsColor: .systemRed))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
            }

            Divider()

            if let error = stockService.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else if settings.items.isEmpty {
                VStack(spacing: 8) {
                    Text("No stocks configured")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Open Settings to add tickers")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        // Chart for primary symbol
                        if settings.showGraph, let quote = stockService.primaryQuote {
                            ChartSectionView(symbol: quote.symbol, isUp: quote.isUp)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            Divider().padding(.horizontal, 12)
                        }

                        ForEach(settings.items) { item in
                            switch item.kind {
                            case .single(let symbol):
                                if let quote = stockService.quote(for: symbol) {
                                    StockRowView(
                                        quote: quote,
                                        isPrimary: symbol == settings.primarySymbol
                                    )
                                }
                            case .category(let name, let icon, let symbols):
                                CategorySectionView(
                                    categoryId: item.id,
                                    name: name,
                                    icon: icon,
                                    symbols: symbols,
                                    primarySymbol: settings.primarySymbol
                                )
                            }
                        }
                    }
                }
                .frame(maxHeight: 400)
            }

            // Ad banner — shown for unlicensed users, or licensed users who opt in
            if !LicenseService.shared.isLicensed || AppSettings.shared.showAdsWhenLicensed {
                AdBannerView()
            }

            Divider()

            // Footer
            HStack {
                if let lastUpdated = stockService.lastUpdated {
                    Text("Updated: \(lastUpdated, formatter: timeFormatter)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Settings…") { onSettings() }
                    .buttonStyle(.borderless)
                    .font(.caption)

                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Category Section

struct CategorySectionView: View {
    let categoryId: UUID
    let name: String
    let icon: String
    let symbols: [String]
    let primarySymbol: String
    @State private var isExpanded = false
    @State private var isHovering = false

    @ObservedObject private var stockService = StockService.shared
    @ObservedObject private var settings = AppSettings.shared

    private var sortOrder: CategorySortOrder { settings.sortOrder(for: categoryId) }

    private var sortedSymbols: [String] {
        stockService.sortedSymbols(symbols, by: sortOrder)
    }

    private var categoryQuotes: [StockQuote] {
        symbols.compactMap { stockService.quote(for: $0) }
    }

    private var categorySummary: String {
        let quotes = categoryQuotes
        guard !quotes.isEmpty else { return "No data" }
        let avgChange = quotes.map(\.changePercent).reduce(0, +) / Double(quotes.count)
        let sign = avgChange >= 0 ? "+" : ""
        return "\(quotes.count) stocks  \(sign)\(String(format: "%.2f%%", avgChange)) avg"
    }

    private var categoryIsUp: Bool {
        let quotes = categoryQuotes
        guard !quotes.isEmpty else { return true }
        return quotes.map(\.changePercent).reduce(0, +) >= 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Category header
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(.accentColor)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(name)
                            .font(.system(.body, weight: .semibold))
                        Text(categorySummary)
                            .font(.caption2)
                            .foregroundColor(categoryIsUp ? .green : .red)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isHovering ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }

            // Expanded tickers
            if isExpanded {
                VStack(spacing: 0) {
                    // Sort picker
                    HStack(spacing: 4) {
                        Text("\(symbols.count) stocks")
                            .font(.caption2)
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                        Spacer()
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.accentColor)
                        Picker("", selection: Binding(
                            get: { sortOrder },
                            set: { settings.setSortOrder($0, for: categoryId) }
                        )) {
                            ForEach(CategorySortOrder.allCases, id: \.rawValue) { order in
                                Text(order.label).tag(order)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 170)
                        .font(.caption2)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 4)

                    ForEach(sortedSymbols, id: \.self) { symbol in
                        if let quote = stockService.quote(for: symbol) {
                            StockRowView(
                                quote: quote,
                                isPrimary: symbol == primarySymbol,
                                indented: true
                            )
                        }
                    }
                }
                .padding(.leading, 8)
            }

            Divider().padding(.horizontal, 12)
        }
    }
}

// MARK: - Stock Row

struct StockRowView: View {
    let quote: StockQuote
    let isPrimary: Bool
    var indented: Bool = false
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var stockService = StockService.shared
    @State private var isHovering = false
    @State private var isExpanded = false

    private let labelColor = Color(nsColor: .tertiaryLabelColor)
    private let valueColor = Color(nsColor: .secondaryLabelColor)
    private var changeColor: Color { quote.isUp ? Color(nsColor: .systemGreen) : Color(nsColor: .systemRed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main row — click to expand
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                if isExpanded { stockService.fetchNews(for: quote.symbol) }
            }) {
                VStack(alignment: .leading, spacing: 5) {
                    // Row 1: Symbol + Price
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(quote.symbol)
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                if isPrimary {
                                    Image(systemName: "star.fill")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                            }
                            Text(quote.shortCompanyName)
                                .font(.caption)
                                .foregroundColor(valueColor)
                                .lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(quote.formattedPrice)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            HStack(spacing: 2) {
                                Image(systemName: quote.isUp ? "arrow.up.right" : "arrow.down.right")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                Text(quote.formattedChange)
                                    .font(.system(.caption, weight: .medium))
                            }
                            .foregroundColor(changeColor)

                            // Holdings value
                            if settings.showHoldings {
                                let shares = settings.sharesFor(quote.symbol)
                                if shares > 0 {
                                    let value = quote.price * shares
                                    let dayPL = quote.change * shares
                                    VStack(alignment: .trailing, spacing: 1) {
                                        HStack(spacing: 3) {
                                            Text(String(format: "%g", shares))
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                            Text("shares")
                                                .font(.caption2)
                                                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                                            Text(String(format: "$%.2f", value))
                                                .font(.system(.caption2, design: .monospaced, weight: .semibold))
                                                .foregroundColor(.primary)
                                        }
                                        HStack(spacing: 2) {
                                            Text("P/L:")
                                                .font(.system(size: 9))
                                                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                                            Text(String(format: "%@$%.2f", dayPL >= 0 ? "+" : "", dayPL))
                                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                                .foregroundColor(changeColor)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Row 2: Market cap, volume, exchange, sector
                    if settings.detailLevel.rawValue >= DropdownDetailLevel.standard.rawValue {
                        HStack(spacing: 8) {
                            if let mc = quote.marketCap {
                                InfoPill(label: "MCap", value: mc)
                            }
                            if let vol = quote.formattedVolume {
                                InfoPill(label: "Vol", value: vol)
                            }
                            if !quote.exchange.isEmpty {
                                Text(quote.exchange)
                                    .font(.system(.caption2, weight: .medium))
                                    .foregroundColor(valueColor)
                            }
                            Spacer()
                            if let sector = quote.sector {
                                Text(sector)
                                    .font(.system(.caption2, weight: .medium))
                                    .foregroundColor(valueColor)
                                    .lineLimit(1)
                            }
                        }
                    }

                    // Row 3: Ranges (detailed)
                    if settings.detailLevel == .detailed {
                        HStack(spacing: 8) {
                            if let range = quote.formattedDayRange {
                                InfoPill(label: "Day", value: range)
                            }
                            if let range52 = quote.formatted52WeekRange {
                                InfoPill(label: "52W", value: range52)
                            }
                            Spacer()
                        }

                        if let pos = quote.fiftyTwoWeekPosition {
                            HStack(spacing: 4) {
                                Text("52W")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(labelColor)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color.primary.opacity(0.08))
                                            .frame(height: 5)
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(pos > 0.5 ? Color(nsColor: .systemGreen) : Color(nsColor: .systemRed))
                                            .frame(width: max(5, geo.size.width * pos), height: 5)
                                    }
                                }
                                .frame(height: 5)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.leading, indented ? 12 : 0)
                .padding(.vertical, 8)
                .background(isHovering ? Color.accentColor.opacity(0.12) : (isPrimary ? Color.accentColor.opacity(0.06) : Color.clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }

            // Expanded: Earnings + News + Yahoo Finance link
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Divider().padding(.horizontal, 4)

                    // Next earnings call
                    if stockService.newsSymbol == quote.symbol {
                        if let date = stockService.earningsDate {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.caption)
                                    .foregroundColor(date == "TBA" ? .secondary : .orange)
                                Text("Next Earnings:")
                                    .font(.system(.caption, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text(date)
                                    .font(.system(.caption, weight: .bold))
                                    .foregroundColor(date == "TBA" ? .secondary : .orange)
                                Spacer()
                            }
                        } else if stockService.newsLoading {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.4)
                                Text("Loading earnings date...")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                    }

                    // Latest news
                    if stockService.newsLoading && stockService.newsSymbol == quote.symbol {
                        HStack {
                            ProgressView().scaleEffect(0.5)
                            Text("Loading news...")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } else if stockService.newsSymbol == quote.symbol && !stockService.newsItems.isEmpty {
                        Text("Latest News")
                            .font(.system(.caption, weight: .bold))
                            .foregroundColor(.primary)

                        ForEach(stockService.newsItems.prefix(4)) { item in
                            Button(action: {
                                if let url = URL(string: item.link) {
                                    NSWorkspace.shared.open(url)
                                }
                            }) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.caption2)
                                        .foregroundColor(.primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Text(item.publisher)
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 3)
                                .padding(.horizontal, 4)
                                .background(Color.accentColor.opacity(0.04))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    } else if stockService.newsSymbol == quote.symbol {
                        Text("No recent news")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Divider().padding(.horizontal, 4)

                    // Yahoo Finance link
                    Button(action: {
                        if let url = quote.yahooFinanceURL { NSWorkspace.shared.open(url) }
                    }) {
                        HStack {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.caption)
                            Text("Open on Yahoo Finance")
                                .font(.caption)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                        }
                        .foregroundColor(.accentColor)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, indented ? 24 : 12)
                .padding(.bottom, 8)
            }
        }
    }
}

// MARK: - Chart Section with Range Tabs

struct ChartSectionView: View {
    let symbol: String
    let isUp: Bool
    @ObservedObject private var stockService = StockService.shared
    @State private var selectedRange: ChartRange = .month

    private var data: [Double] { stockService.chartData }
    private var chartIsUp: Bool {
        guard let first = data.first, let last = data.last else { return isUp }
        return last >= first
    }
    private var lineColor: Color { chartIsUp ? Color(nsColor: .systemGreen) : Color(nsColor: .systemRed) }

    var body: some View {
        VStack(spacing: 6) {
            // Header: symbol + change %
            HStack {
                Text(symbol)
                    .font(.system(.caption, weight: .bold))
                    .foregroundColor(.primary)
                if let first = data.first, let last = data.last, first != 0 {
                    let pct = ((last - first) / first) * 100
                    let sign = pct >= 0 ? "+" : ""
                    Text("\(sign)\(String(format: "%.1f%%", pct))")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(lineColor)
                }
                Spacer()
                if stockService.chartLoading {
                    ProgressView().scaleEffect(0.5)
                }
            }

            // Range tabs
            HStack(spacing: 0) {
                ForEach(ChartRange.allCases, id: \.rawValue) { range in
                    Button(action: {
                        selectedRange = range
                        stockService.fetchChartData(symbol: symbol, range: range)
                    }) {
                        Text(range.label)
                            .font(.system(size: 10, weight: selectedRange == range ? .bold : .medium))
                            .foregroundColor(selectedRange == range ? .white : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(selectedRange == range ? lineColor.opacity(0.8) : Color.clear)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Chart
            if data.count >= 2 {
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    let minVal = data.min() ?? 0
                    let maxVal = data.max() ?? 1
                    let valRange = maxVal - minVal > 0 ? maxVal - minVal : 1
                    let stepX = w / CGFloat(data.count - 1)

                    let points: [CGPoint] = data.enumerated().map { i, val in
                        CGPoint(x: CGFloat(i) * stepX, y: h - ((CGFloat(val - minVal) / CGFloat(valRange)) * h * 0.9 + h * 0.05))
                    }

                    // Fill
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: h))
                        for p in points { path.addLine(to: p) }
                        path.addLine(to: CGPoint(x: w, y: h))
                        path.closeSubpath()
                    }
                    .fill(lineColor.opacity(0.12))

                    // Line
                    Path { path in
                        for (i, p) in points.enumerated() {
                            if i == 0 { path.move(to: p) }
                            else { path.addLine(to: p) }
                        }
                    }
                    .stroke(lineColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                    // End dot
                    if let last = points.last {
                        Circle().fill(lineColor).frame(width: 5, height: 5).position(last)
                    }
                }
                .frame(height: 70)
            } else if !stockService.chartLoading {
                Text("No chart data")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(height: 70)
            }
        }
        .onAppear {
            stockService.fetchChartData(symbol: symbol, range: selectedRange)
        }
    }
}

// MARK: - Info Pill (label: value pair)

struct InfoPill: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 2) {
            Text("\(label):")
                .font(.system(.caption2, weight: .semibold))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            Text(value)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        }
    }
}

// MARK: - Ad Banner

struct AdBannerView: View {
    @ObservedObject private var adService = AdService.shared
    @State private var isHovering = false

    var body: some View {
        Button(action: openAd) {
            VStack(spacing: 0) {
                switch adService.currentAd.resolvedType {
                case .text:
                    textAdView
                case .banner:
                    bannerAdView
                }
            }
            .background(isHovering ? Color.accentColor.opacity(0.06) : Color(nsColor: .controlBackgroundColor).opacity(0.3))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .onAppear { adService.rotateAd() }
    }

    // MARK: - Text Ad
    private var textAdView: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if let text = adService.currentAd.text {
                    Text(text)
                        .font(.caption2)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Text("Sponsored by \(adService.currentAd.sponsor)")
                    .font(.system(size: 9))
                    .foregroundColor(Color(nsColor: .tertiaryLabelColor))
            }
            Spacer()
            if let cta = adService.currentAd.ctaText {
                Text(cta)
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor)
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Banner Ad
    private var bannerAdView: some View {
        VStack(spacing: 2) {
            if let image = adService.bannerImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 60)
                    .cornerRadius(4)
            } else {
                // Loading placeholder
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(height: 50)
                    .overlay(ProgressView().scaleEffect(0.5))
            }
            Text("Ad · \(adService.currentAd.sponsor)")
                .font(.system(size: 8))
                .foregroundColor(Color(nsColor: .tertiaryLabelColor))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func openAd() {
        let ad = adService.currentAd
        guard !ad.url.isEmpty, let url = URL(string: ad.url) else { return }
        NSWorkspace.shared.open(url)
        AnalyticsService.shared.track("ad_clicked", properties: [
            "sponsor": ad.sponsor,
            "type": ad.resolvedType.rawValue,
        ])
    }
}

private let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.timeStyle = .short
    return f
}()

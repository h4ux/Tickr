import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var stockService = StockService.shared
    @State private var newSymbol = ""
    @State private var showError = false
    @State private var errorText = ""
    @State private var showAddCategory = false
    @State private var newCategoryName = ""
    @State private var newCategoryIcon = "folder"

    var body: some View {
        VStack(spacing: 0) {
            Text("Tickr Settings")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top, 16)
                .padding(.bottom, 8)

            TabView {
                appearanceTab
                    .tabItem { Label("Appearance", systemImage: "paintpalette") }

                generalTab
                    .tabItem { Label("General", systemImage: "gearshape") }

                licenseTab
                    .tabItem { Label("License", systemImage: "key.fill") }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Tabs

    @ViewBuilder
    private var appearanceTab: some View {
        VStack(spacing: 0) {
            Form {
                menuBarAppearanceSection
                SuggestionsSection()
                tickersCategoriesSection
            }
            .formStyle(.grouped)

            HStack {
                Text("Click ★ to set menu bar ticker  •  Drag to reorder")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                if stockService.isLoading {
                    ProgressView().scaleEffect(0.5)
                }
                Button(action: { stockService.fetchQuotes() }) {
                    Image(systemName: "arrow.clockwise")
                    Text("Refresh")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(stockService.isLoading)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var generalTab: some View {
        Form {
            Section("Refresh Interval") {
                Picker("Update every:", selection: $settings.refreshInterval) {
                    ForEach(AppSettings.refreshIntervals, id: \.seconds) { interval in
                        Text(interval.label).tag(interval.seconds)
                    }
                }
                .pickerStyle(.menu)
            }
            LaunchAtLoginSection()
            UpdateSection()
            AnalyticsSection()
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var licenseTab: some View {
        Form {
            LicenseSection()
        }
        .formStyle(.grouped)
    }

    // MARK: - Sections

    @ViewBuilder
    private var menuBarAppearanceSection: some View {
        Section("Menu Bar Appearance") {
            Picker("Display:", selection: $settings.displayFormat) {
                ForEach(TickerDisplayFormat.allCases, id: \.rawValue) { format in
                    Text(format.label).tag(format)
                }
            }
            .pickerStyle(.menu)

            Picker("Trend indicator:", selection: $settings.trendStyle) {
                ForEach(TickerTrendStyle.allCases, id: \.rawValue) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.menu)

            Picker("Color:", selection: $settings.colorMode) {
                ForEach(TickerColorMode.allCases, id: \.rawValue) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.menu)

            Picker("Dropdown detail:", selection: $settings.detailLevel) {
                ForEach(DropdownDetailLevel.allCases, id: \.rawValue) { level in
                    Text(level.label).tag(level)
                }
            }
            .pickerStyle(.menu)

            Toggle("Show 1-month chart for primary ticker", isOn: $settings.showGraph)

            Toggle("Show portfolio holdings value", isOn: $settings.showHoldings)

            Picker("Menu bar ticker:", selection: $settings.primarySymbol) {
                ForEach(settings.allSymbols, id: \.self) { symbol in
                    HStack {
                        Text(symbol)
                        if let q = stockService.quote(for: symbol) {
                            Text("- \(q.shortCompanyName)")
                                .foregroundColor(.secondary)
                        }
                    }.tag(symbol)
                }
            }
            .pickerStyle(.menu)

            RotationSettingsView()

            HStack {
                Text("Preview:")
                    .foregroundColor(.secondary)
                Spacer()
                Text(previewText)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(previewColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
        }
    }

    @ViewBuilder
    private var tickersCategoriesSection: some View {
        Section("Tickers & Categories (\(settings.totalSymbolCount) symbols)") {
            HStack {
                TextField("Add ticker (e.g. AAPL)", text: $newSymbol)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addSingleTicker() }

                Button("Add Ticker") { addSingleTicker() }
                    .disabled(newSymbol.trimmingCharacters(in: .whitespaces).isEmpty)

                Button(action: { showAddCategory.toggle() }) {
                    Image(systemName: "folder.badge.plus")
                }
                .help("Add category")
            }

            if showError {
                Text(errorText)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if showAddCategory {
                HStack {
                    Picker("", selection: $newCategoryIcon) {
                        ForEach(AppSettings.categoryIcons, id: \.self) { icon in
                            Image(systemName: icon).tag(icon)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 60)

                    TextField("Category name", text: $newCategoryName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addCategory() }

                    Button("Create") { addCategory() }
                        .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button(action: { showAddCategory = false }) {
                        Image(systemName: "xmark.circle")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 2)
            }

            List {
                ForEach(Array(settings.items.enumerated()), id: \.element.id) { index, item in
                    switch item.kind {
                    case .single(let symbol):
                        SingleTickerRow(
                            symbol: symbol,
                            isPrimary: symbol == settings.primarySymbol,
                            onSetPrimary: { settings.primarySymbol = symbol },
                            onDelete: { settings.removeItem(at: IndexSet(integer: index)) }
                        )
                    case .category(let name, let icon, let symbols):
                        CategorySettingsRow(
                            itemId: item.id,
                            name: name,
                            icon: icon,
                            symbols: symbols,
                            onDelete: { settings.removeItem(at: IndexSet(integer: index)) }
                        )
                    }
                }
                .onDelete { indices in
                    settings.removeItem(at: indices)
                }
                .onMove { from, to in
                    var updated = settings.items
                    updated.move(fromOffsets: from, toOffset: to)
                    settings.items = updated
                }
            }
            .frame(minHeight: 200)
        }
    }

    // MARK: - Preview

    private var previewText: String {
        if let quote = stockService.primaryQuote {
            return quote.menuBarText(format: settings.displayFormat, trend: settings.trendStyle)
        }
        let sample = StockQuote(symbol: "AAPL", companyName: "Apple Inc.", price: 185.50, change: 2.30, changePercent: 1.25, previousClose: 183.20, dayHigh: 186.00, dayLow: 183.00, volume: 52_340_000, fiftyTwoWeekHigh: 199.62, fiftyTwoWeekLow: 124.17, currency: "USD", exchange: "NASDAQ", sector: "Technology", industry: "Consumer Electronics", marketCap: "3.76T")
        return sample.menuBarText(format: settings.displayFormat, trend: settings.trendStyle)
    }

    private var previewColor: Color {
        let isUp = stockService.primaryQuote?.isUp ?? true
        switch settings.colorMode {
        case .colored: return isUp ? .green : .red
        case .grey:    return .primary
        }
    }

    // MARK: - Actions

    private func addSingleTicker() {
        showError = false
        let cleaned = newSymbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return }

        if settings.allSymbols.contains(cleaned) {
            errorText = "\(cleaned) is already in your list"
            showError = true
            return
        }
        if settings.addSingleTicker(cleaned) {
            newSymbol = ""
        } else {
            errorText = "Invalid ticker symbol"
            showError = true
        }
    }

    private func addCategory() {
        let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        settings.addCategory(name: trimmed, icon: newCategoryIcon)
        newCategoryName = ""
        newCategoryIcon = "folder"
        showAddCategory = false
    }
}

// MARK: - Single Ticker Row

struct SingleTickerRow: View {
    let symbol: String
    let isPrimary: Bool
    let onSetPrimary: () -> Void
    let onDelete: () -> Void
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var stockService = StockService.shared
    @State private var sharesText: String = ""

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Button(action: onSetPrimary) {
                    Image(systemName: isPrimary ? "star.fill" : "star")
                        .foregroundColor(isPrimary ? .yellow : .secondary)
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Text(symbol)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(isPrimary ? .bold : .regular)

                if let quote = stockService.quote(for: symbol) {
                    Text(quote.shortCompanyName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isPrimary {
                    Text("Menu Bar")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(4)
                }

                if !settings.categories.isEmpty {
                    Menu {
                        ForEach(settings.categories, id: \.id) { cat in
                            Button(cat.name) {
                                settings.moveTickerToCategory(symbol: symbol, categoryId: cat.id)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.right.square")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 20)
                    .help("Move to category")
                }

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.7))
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Remove \(symbol)")
            }

            // Holdings input
            if settings.showHoldings {
                HStack(spacing: 6) {
                    Text("Shares:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    TextField("0", text: $sharesText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 70)
                        .onSubmit { saveShares() }
                        .onChange(of: sharesText) { _ in saveShares() }
                    if let quote = stockService.quote(for: symbol), settings.sharesFor(symbol) > 0 {
                        let value = quote.price * settings.sharesFor(symbol)
                        Text(String(format: "= $%.2f", value))
                            .font(.system(.caption, design: .monospaced, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    Spacer()
                }
                .padding(.leading, 28)
            }
        }
        .contentShape(Rectangle())
        .onAppear {
            let shares = settings.sharesFor(symbol)
            sharesText = shares > 0 ? String(format: "%g", shares) : ""
        }
    }

    private func saveShares() {
        let value = Double(sharesText) ?? 0
        settings.setShares(value, for: symbol)
    }
}

// MARK: - Category Settings Row

struct CategorySettingsRow: View {
    let itemId: UUID
    let name: String
    let icon: String
    let symbols: [String]
    let onDelete: () -> Void

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var stockService = StockService.shared
    @State private var isExpanded = false
    @State private var newSymbol = ""
    @State private var isEditingName = false
    @State private var editName = ""
    @State private var isEditingIcon = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Category header
            HStack(spacing: 6) {
                // Icon — click to change
                Button(action: { isEditingIcon.toggle() }) {
                    Image(systemName: icon)
                        .foregroundColor(.accentColor)
                        .font(.system(size: 14))
                        .frame(width: 20)
                }
                .buttonStyle(.borderless)
                .help("Change icon")

                // Name — inline edit
                if isEditingName {
                    TextField("Name", text: $editName, onCommit: {
                        if !editName.trimmingCharacters(in: .whitespaces).isEmpty {
                            settings.renameCategory(itemId: itemId, newName: editName)
                        }
                        isEditingName = false
                    })
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)
                    .font(.caption)

                    Button(action: { isEditingName = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                } else {
                    Text(name)
                        .fontWeight(.semibold)

                    Text("(\(symbols.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !isEditingName {
                    // Edit name button
                    Button(action: {
                        editName = name
                        isEditingName = true
                    }) {
                        Image(systemName: "pencil")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Rename category")

                    // Delete category button
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red.opacity(0.7))
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete category and all its tickers")

                    // Expand/collapse
                    Button(action: { withAnimation { isExpanded.toggle() } }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }

            // Icon picker
            if isEditingIcon {
                HStack(spacing: 4) {
                    Text("Pick icon:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 2), count: 8), spacing: 4) {
                        ForEach(AppSettings.categoryIcons, id: \.self) { iconName in
                            Button(action: {
                                settings.updateCategoryIcon(itemId: itemId, newIcon: iconName)
                                isEditingIcon = false
                            }) {
                                Image(systemName: iconName)
                                    .font(.system(size: 13))
                                    .frame(width: 26, height: 26)
                                    .background(iconName == icon ? Color.accentColor.opacity(0.25) : Color.clear)
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(iconName == icon ? .accentColor : .secondary)
                        }
                    }
                }
                .padding(.leading, 26)
                .padding(.vertical, 2)
            }

            // Expanded: show symbols + add field
            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    // Add ticker to category
                    HStack {
                        TextField("Add ticker to \(name)", text: $newSymbol)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .onSubmit { addToCategory() }

                        Button("Add") { addToCategory() }
                            .font(.caption)
                            .disabled(newSymbol.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if symbols.isEmpty {
                        Text("No tickers in this category yet")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 8)
                    }

                    // Symbol list
                    ForEach(Array(symbols.enumerated()), id: \.offset) { idx, symbol in
                        CategorySymbolRow(
                            symbol: symbol,
                            itemId: itemId,
                            symbolIndex: idx
                        )
                        .padding(.leading, 8)
                    }
                }
                .padding(.leading, 20)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
    }

    private func addToCategory() {
        let cleaned = newSymbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        if settings.addSymbolToCategory(itemId: itemId, symbol: cleaned) {
            newSymbol = ""
        }
    }
}

// MARK: - Rotation Settings

struct RotationSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var stockService = StockService.shared
    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Rotate tickers in menu bar", isOn: $settings.rotationEnabled)

            if settings.rotationEnabled {
                Picker("Rotate every:", selection: $settings.rotationInterval) {
                    ForEach(AppSettings.rotationIntervals, id: \.seconds) { interval in
                        Text(interval.label).tag(interval.seconds)
                    }
                }
                .pickerStyle(.menu)

                // Current rotation list
                HStack {
                    Text("Tickers (\(settings.rotatingSymbols.count)/5):")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if settings.rotatingSymbols.count < 5 {
                        Button(action: { showPicker.toggle() }) {
                            Image(systemName: "plus.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                // Symbol chips
                if !settings.rotatingSymbols.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(settings.rotatingSymbols, id: \.self) { symbol in
                            HStack(spacing: 3) {
                                Text(symbol)
                                    .font(.system(.caption2, design: .monospaced, weight: .medium))
                                Button(action: {
                                    settings.rotatingSymbols.removeAll { $0 == symbol }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(4)
                        }
                    }
                } else {
                    Text("Add tickers to rotate in the menu bar")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Picker to add symbols
                if showPicker {
                    let available = settings.allSymbols.filter { !settings.rotatingSymbols.contains($0) }
                    if available.isEmpty {
                        Text("All tickers already added")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                ForEach(available, id: \.self) { symbol in
                                    Button(action: {
                                        if settings.rotatingSymbols.count < 5 {
                                            settings.rotatingSymbols.append(symbol)
                                        }
                                        if settings.rotatingSymbols.count >= 5 { showPicker = false }
                                    }) {
                                        HStack(spacing: 3) {
                                            Text(symbol)
                                                .font(.system(.caption2, design: .monospaced))
                                            if let q = stockService.quote(for: symbol) {
                                                Text(q.shortCompanyName)
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.secondary.opacity(0.08))
                                        .cornerRadius(4)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Category Symbol Row (with holdings)

struct CategorySymbolRow: View {
    let symbol: String
    let itemId: UUID
    let symbolIndex: Int
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var stockService = StockService.shared
    @State private var sharesText: String = ""

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Button(action: { settings.primarySymbol = symbol }) {
                    Image(systemName: symbol == settings.primarySymbol ? "star.fill" : "star")
                        .foregroundColor(symbol == settings.primarySymbol ? .yellow : .secondary)
                        .font(.caption2)
                }
                .buttonStyle(.borderless)

                Text(symbol)
                    .font(.system(.caption, design: .monospaced))

                if let quote = stockService.quote(for: symbol) {
                    Text(quote.shortCompanyName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if symbol == settings.primarySymbol {
                    Text("Menu Bar")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15))
                        .cornerRadius(3)
                }

                Menu {
                    Button("Make standalone") {
                        settings.moveTickerToStandalone(symbol: symbol, fromCategoryId: itemId)
                    }
                    let otherCats = settings.categories.filter { $0.id != itemId }
                    if !otherCats.isEmpty {
                        Divider()
                        ForEach(otherCats, id: \.id) { cat in
                            Button("Move to \(cat.name)") {
                                settings.moveTickerToCategory(symbol: symbol, categoryId: cat.id)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.right.square")
                        .foregroundColor(.secondary)
                        .font(.caption2)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 18)
                .help("Move ticker")

                Button(action: {
                    settings.removeSymbolFromCategory(itemId: itemId, symbolIndex: IndexSet(integer: symbolIndex))
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.7))
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .help("Remove \(symbol)")
            }

            // Holdings input
            if settings.showHoldings {
                HStack(spacing: 6) {
                    Text("Shares:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    TextField("0", text: $sharesText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption2, design: .monospaced))
                        .frame(width: 60)
                        .onSubmit { saveShares() }
                        .onChange(of: sharesText) { _ in saveShares() }
                    if let quote = stockService.quote(for: symbol), settings.sharesFor(symbol) > 0 {
                        let value = quote.price * settings.sharesFor(symbol)
                        Text(String(format: "= $%.2f", value))
                            .font(.system(.caption2, design: .monospaced, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    Spacer()
                }
                .padding(.leading, 20)
            }
        }
        .onAppear {
            let shares = settings.sharesFor(symbol)
            sharesText = shares > 0 ? String(format: "%g", shares) : ""
        }
    }

    private func saveShares() {
        settings.setShares(Double(sharesText) ?? 0, for: symbol)
    }
}

// MARK: - License Section

struct LicenseSection: View {
    @ObservedObject private var license = LicenseService.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var email = ""
    @State private var key = ""
    @State private var showError = false

    var body: some View {
        Section {
            if license.isLicensed {
                // Licensed state
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tickr Pro")
                            .font(.system(.body, weight: .bold))
                        Text("Licensed to \(license.licensedEmail)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Deactivate") { license.deactivate() }
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Toggle("Show ads (support Tickr)", isOn: $settings.showAdsWhenLicensed)
                    .font(.caption)
            } else {
                // Unlicensed — show activation form
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "key")
                            .foregroundColor(.accentColor)
                        Text("Enter license to remove ads")
                            .font(.system(.body, weight: .medium))
                    }

                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)

                    TextField("License key (XXXXX-XXXXX-XXXXX-XXXXX-XXXXX)", text: $key)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))

                    if showError {
                        Text("Invalid license key. Please check your email and key.")
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    HStack {
                        Button("Activate") {
                            showError = false
                            if !license.activate(email: email, key: key) {
                                showError = true
                            }
                        }
                        .disabled(email.isEmpty || key.isEmpty)

                        Spacer()

                        Button("Get a License") {
                            if let url = URL(string: "https://github.com/h4ux/Tickr") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    }
                }
            }
        } header: {
            Text("License")
        }
    }
}

// MARK: - Update Section

struct UpdateSection: View {
    @ObservedObject private var updater = UpdateService.shared

    var body: some View {
        Section {
            // Auto-check toggle
            Toggle("Automatically check for updates", isOn: Binding(
                get: { updater.autoCheckEnabled },
                set: { updater.autoCheckEnabled = $0 }
            ))

            // Current version
            HStack {
                Text("Current version:")
                    .foregroundColor(.secondary)
                Spacer()
                Text("v\(UpdateService.currentVersion)")
                    .font(.system(.body, design: .monospaced))
            }

            // Latest version / update status
            if let latest = updater.latestVersion {
                HStack {
                    Text("Latest version:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("v\(latest)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(updater.updateAvailable ? Color(nsColor: .systemGreen) : .secondary)
                }
            }

            // Update available banner
            if updater.updateAvailable {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.green)
                        Text("Update available!")
                            .font(.system(.body, weight: .semibold))
                            .foregroundColor(.primary)
                        Spacer()
                        if let size = updater.downloadSize {
                            Text(size)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Release notes
                    if let notes = updater.releaseNotes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(4)
                    }

                    // Download progress
                    if updater.isDownloading {
                        VStack(spacing: 4) {
                            ProgressView(value: updater.downloadProgress)
                            Text("Downloading... \(Int(updater.downloadProgress * 100))%")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Button(action: { updater.downloadAndInstall() }) {
                            HStack {
                                Image(systemName: "arrow.down.app")
                                Text("Download & Install")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.vertical, 4)
            } else if updater.latestVersion != nil && !updater.updateAvailable {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("You're up to date!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Error message
            if let error = updater.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Check now button + last checked
            HStack {
                Button(action: { updater.checkForUpdates() }) {
                    HStack(spacing: 4) {
                        if updater.isChecking {
                            ProgressView().scaleEffect(0.5)
                        }
                        Text(updater.isChecking ? "Checking..." : "Check for Updates")
                    }
                }
                .disabled(updater.isChecking)

                Spacer()

                if let last = updater.lastChecked {
                    Text("Last checked: \(last, formatter: updateTimeFormatter)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("Updates")
        }
    }
}

// MARK: - Launch at Login Section

struct LaunchAtLoginSection: View {
    @ObservedObject private var launcher = LaunchAtLoginService.shared
    @State private var showHelp = false

    var body: some View {
        Section {
            HStack {
                Toggle("Launch Tickr at login", isOn: Binding(
                    get: { launcher.isEnabled },
                    set: { launcher.setEnabled($0) }
                ))
                Button(action: { showHelp.toggle() }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
                .help("How Launch at Login works")
            }

            // Status line
            HStack {
                Text("Status:")
                    .foregroundColor(.secondary)
                Spacer()
                Text(launcher.statusDescription)
                    .font(.caption)
                    .foregroundColor(launcher.isEnabled ? Color(nsColor: .systemGreen) : .secondary)
            }

            // Approval required — explain what to do
            if launcher.needsApproval {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Approval needed in System Settings")
                            .font(.system(.caption, weight: .semibold))
                    }
                    Text("macOS needs your permission to let Tickr launch automatically. Open System Settings and enable Tickr under Login Items.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Button("Open Login Items Settings") {
                        launcher.openLoginItemsSettings()
                    }
                    .font(.caption)
                }
                .padding(.vertical, 4)
            }

            // Error
            if let error = launcher.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Help / explainer
            if showHelp {
                VStack(alignment: .leading, spacing: 6) {
                    Text("How it works")
                        .font(.system(.caption, weight: .semibold))
                    Text("Turning this on registers Tickr as a login item so it starts automatically when you log in to your Mac.")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("If something goes wrong")
                        .font(.system(.caption, weight: .semibold))
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Open System Settings → General → Login Items", systemImage: "1.circle")
                        Label("Find \"Tickr\" under \"Open at Login\" and toggle it on", systemImage: "2.circle")
                        Label("If Tickr isn't listed, toggle this switch off and on again", systemImage: "3.circle")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)

                    Button("Open Login Items Settings") {
                        launcher.openLoginItemsSettings()
                    }
                    .font(.caption)
                    .padding(.top, 2)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Startup")
        }
        .onAppear { launcher.refresh() }
    }
}

private let updateTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .short
    f.timeStyle = .short
    return f
}()

// MARK: - Suggestions Section

struct SuggestionsSection: View {
    @ObservedObject private var suggestions = SuggestionsService.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var expandedGroup: String?

    var body: some View {
        Section {
            if suggestions.groups.isEmpty {
                Text("Loading suggestions...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(suggestions.groups) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        // Group header — tap to expand
                        Button(action: {
                            withAnimation { expandedGroup = expandedGroup == group.name ? nil : group.name }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: group.icon)
                                    .foregroundColor(.accentColor)
                                    .font(.system(size: 13))
                                    .frame(width: 18)
                                Text(group.name)
                                    .font(.system(.caption, weight: .semibold))
                                Text("(\(group.symbols.count))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()

                                // Add entire group as category
                                Button(action: { addGroup(group) }) {
                                    HStack(spacing: 2) {
                                        Image(systemName: "plus.rectangle.on.folder")
                                        Text("Add All")
                                    }
                                    .font(.caption2)
                                    .foregroundColor(.accentColor)
                                }
                                .buttonStyle(.borderless)
                                .help("Add as a new category with all symbols")

                                Image(systemName: expandedGroup == group.name ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        // Expanded: show symbols with individual add buttons
                        if expandedGroup == group.name {
                            FlowLayout(spacing: 4) {
                                ForEach(group.symbols, id: \.self) { symbol in
                                    let alreadyAdded = settings.allSymbols.contains(symbol)
                                    Button(action: {
                                        if !alreadyAdded { _ = settings.addSingleTicker(symbol) }
                                    }) {
                                        HStack(spacing: 3) {
                                            Text(symbol)
                                                .font(.system(.caption2, design: .monospaced, weight: .medium))
                                            if alreadyAdded {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 8))
                                                    .foregroundColor(.green)
                                            } else {
                                                Image(systemName: "plus.circle")
                                                    .font(.system(size: 8))
                                                    .foregroundColor(.accentColor)
                                            }
                                        }
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(alreadyAdded ? Color.green.opacity(0.08) : Color.accentColor.opacity(0.08))
                                        .cornerRadius(4)
                                        .foregroundColor(alreadyAdded ? .secondary : .primary)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(alreadyAdded)
                                }
                            }
                            .padding(.leading, 26)
                            .padding(.top, 2)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text("Suggestions")
        }
    }

    private func addGroup(_ group: SuggestedGroup) {
        // Filter out symbols already in the watchlist
        let newSymbols = group.symbols.filter { !settings.allSymbols.contains($0) }
        guard !newSymbols.isEmpty else { return }
        settings.addCategory(name: group.name, icon: group.icon)
        // Find the newly created category and add symbols
        if let item = settings.items.last, case .category = item.kind {
            for symbol in newSymbols {
                _ = settings.addSymbolToCategory(itemId: item.id, symbol: symbol)
            }
        }
    }
}

// Simple flow layout for suggestion chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}

// MARK: - Analytics Section

struct AnalyticsSection: View {
    @ObservedObject private var settings = AppSettings.shared
    @State private var showDetails = false

    var body: some View {
        Section {
            HStack {
                Toggle("Help improve Tickr", isOn: $settings.analyticsEnabled)

                Button(action: { showDetails.toggle() }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
                .help("See exactly what is tracked")
            }

            if showDetails {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tickr collects minimal, anonymous usage data to help improve the app. No personal information is ever collected.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()

                    Text("Events tracked:")
                        .font(.caption)
                        .fontWeight(.semibold)

                    ForEach(AnalyticsService.trackedEvents, id: \.event) { item in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 4))
                                .foregroundColor(.secondary)
                                .padding(.top, 5)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.event)
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.medium)
                                Text(item.description)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Divider()

                    Text("Data sent with each event:")
                        .font(.caption)
                        .fontWeight(.semibold)

                    ForEach(AnalyticsService.commonProperties, id: \.property) { item in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 4))
                                .foregroundColor(.secondary)
                                .padding(.top, 5)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.property)
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.medium)
                                Text(item.description)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 3) {
                        Label("Anonymous ID — no login, no email, no name", systemImage: "person.slash")
                        Label("No IP address tracking", systemImage: "network.slash")
                        Label("No browsing or financial data", systemImage: "lock.shield")
                        Label("Fully opt-out — toggle off to stop all tracking", systemImage: "hand.raised")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Analytics")
        }
    }
}

import AppKit
import SwiftUI
import Combine

class StatusBarController {
    private var statusItem: NSStatusItem
    private var popover: NSPopover
    private let stockService = StockService.shared
    private let settings = AppSettings.shared
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?
    private var rotationTimer: Timer?
    private var rotationIndex = 0
    private var scrollOffset = 0
    private let scrollTickInterval: TimeInterval = 0.18
    private let scrollSeparator = "  •  "
    private var eventMonitor: Any?

    // Single-ticker overflow marquee (used when content > fixed width)
    private var overflowTimer: Timer?
    private var overflowOffset = 0
    private var overflowText: NSAttributedString?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        popover.contentSize = NSSize(width: 420, height: 500)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: TickerDropdownView(
            onSettings: { [weak self] in self?.openSettings() }
        ))

        updateMenuBarDisplay(nil)

        if let button = statusItem.button {
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Any change to quotes or display settings → update menu bar
        Publishers.CombineLatest4(
            stockService.$quotes,
            settings.$primarySymbol,
            settings.$displayFormat,
            settings.$trendStyle
        )
        .combineLatest(settings.$colorMode)
        .receive(on: RunLoop.main)
        .sink { [weak self] _, _ in
            self?.updateCurrentDisplay()
        }
        .store(in: &cancellables)

        // When primary symbol changes, trigger a fetch
        settings.$primarySymbol
            .dropFirst()
            .sink { [weak self] _ in
                self?.stockService.fetchQuotes()
            }
            .store(in: &cancellables)

        // When rotation settings change, restart rotation timer
        settings.$rotationEnabled
            .combineLatest(settings.$rotationInterval, settings.$rotatingSymbols, settings.$rotationMode)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _, _ in
                self?.restartRotationTimer()
            }
            .store(in: &cancellables)

        // Market cap and width changes also force a re-render
        Publishers.CombineLatest(settings.$showMarketCap, settings.$menuBarMaxWidth)
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.updateCurrentDisplay()
            }
            .store(in: &cancellables)

        DispatchQueue.main.async { [weak self] in
            self?.stockService.startFetching()
        }
    }

    // MARK: - Display

    /// Determine which symbol to show: rotation or primary
    private var currentDisplaySymbol: String {
        if settings.rotationEnabled && settings.rotatingSymbols.count > 1 {
            let symbols = settings.rotatingSymbols
            let idx = rotationIndex % symbols.count
            return symbols[idx]
        }
        return settings.primarySymbol
    }

    private var isScrolling: Bool {
        settings.rotationEnabled && settings.rotatingSymbols.count > 1 && settings.rotationMode == .scroll
    }

    private func updateCurrentDisplay() {
        applyStatusItemLength()
        if isScrolling {
            stopOverflowMarquee()
            updateScrollDisplay()
            return
        }
        let symbol = currentDisplaySymbol
        let quote = stockService.quotes.first { $0.symbol == symbol }
        updateMenuBarDisplay(quote)
    }

    private func updateMenuBarDisplay(_ quote: StockQuote?) {
        guard let button = statusItem.button else { return }

        let attributed = buildSingleAttributedString(for: quote)

        // Empty / placeholder fallback
        if attributed.length == 0 {
            stopOverflowMarquee()
            button.title = "Tickr"
            return
        }

        // Fixed-width mode: marquee if overflow.
        if settings.menuBarMaxWidth > 0 {
            let maxChars = availableCharsForFixedWidth()
            if attributed.length > maxChars {
                startOverflowMarquee(text: attributed)
                return
            }
        }

        stopOverflowMarquee()
        button.attributedTitle = attributed
    }

    private func buildSingleAttributedString(for quote: StockQuote?) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        let result = NSMutableAttributedString()

        if let quote = quote {
            let text = quote.menuBarText(format: settings.displayFormat, trend: settings.trendStyle, showMarketCap: settings.showMarketCap)
            let color: NSColor
            switch settings.colorMode {
            case .colored: color = quote.isUp ? .systemGreen : .systemRed
            case .grey:    color = .labelColor
            }
            result.append(NSAttributedString(string: text, attributes: [
                .foregroundColor: color,
                .font: font
            ]))
        } else {
            let symbol = currentDisplaySymbol
            if symbol.isEmpty { return result }
            let text = "\(symbol) ..."
            result.append(NSAttributedString(string: text, attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: font
            ]))
        }
        return result
    }

    // MARK: - Width & overflow marquee

    private func applyStatusItemLength() {
        if settings.menuBarMaxWidth > 0 {
            statusItem.length = CGFloat(settings.menuBarMaxWidth)
        } else {
            statusItem.length = NSStatusItem.variableLength
        }
    }

    private func availableCharsForFixedWidth() -> Int {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        let charW = ("M" as NSString).size(withAttributes: [.font: font]).width
        guard charW > 0 else { return 1 }
        // Reserve ~12pt for the button's inherent inner padding.
        let usable = max(0, CGFloat(settings.menuBarMaxWidth) - 12)
        return max(1, Int(usable / charW))
    }

    private func startOverflowMarquee(text: NSAttributedString) {
        overflowText = text
        if overflowTimer == nil {
            overflowOffset = 0
            let t = Timer(timeInterval: scrollTickInterval, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.overflowOffset += 1
                self.applyOverflowWindow()
            }
            RunLoop.main.add(t, forMode: .common)
            overflowTimer = t
        }
        applyOverflowWindow()
    }

    private func stopOverflowMarquee() {
        overflowTimer?.invalidate()
        overflowTimer = nil
        overflowText = nil
        overflowOffset = 0
    }

    private func applyOverflowWindow() {
        guard let button = statusItem.button, let text = overflowText else { return }
        let windowSize = availableCharsForFixedWidth()

        let sep = NSAttributedString(string: scrollSeparator, attributes: [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        ])
        let doubled = NSMutableAttributedString(attributedString: text)
        doubled.append(sep)
        doubled.append(text)

        let cycleLen = text.length + sep.length
        let offset = overflowOffset % max(cycleLen, 1)
        let len = min(windowSize, doubled.length - offset)
        button.attributedTitle = doubled.attributedSubstring(from: NSRange(location: offset, length: len))
    }

    // MARK: - Rotation Timer

    private func restartRotationTimer() {
        rotationTimer?.invalidate()
        rotationTimer = nil

        guard settings.rotationEnabled && settings.rotatingSymbols.count > 1 else {
            // Rotation disabled — show the primary ticker.
            updateCurrentDisplay()
            return
        }

        switch settings.rotationMode {
        case .swap:
            rotationIndex = 0
            let t = Timer(timeInterval: settings.rotationInterval, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.rotationIndex += 1
                self.updateCurrentDisplay()
            }
            RunLoop.main.add(t, forMode: .common)
            rotationTimer = t
            updateCurrentDisplay()

        case .scroll:
            scrollOffset = 0
            let t = Timer(timeInterval: scrollTickInterval, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.scrollOffset += 1
                self.updateScrollDisplay()
            }
            RunLoop.main.add(t, forMode: .common)
            rotationTimer = t
            updateScrollDisplay()
        }
    }

    // MARK: - Scroll (marquee) mode

    private func updateScrollDisplay() {
        guard let button = statusItem.button else { return }

        let full = buildScrollAttributedString()
        guard full.length > 0 else {
            button.title = "Tickr"
            return
        }

        // Double the string so the visible window can wrap seamlessly.
        let doubled = NSMutableAttributedString(attributedString: full)
        doubled.append(full)

        let totalLen = full.length
        // Use the configured menu-bar width if set, else default to 40 chars.
        let configured = settings.menuBarMaxWidth > 0 ? availableCharsForFixedWidth() : 40
        let windowSize = min(configured, totalLen)
        let offset = scrollOffset % max(totalLen, 1)
        button.attributedTitle = doubled.attributedSubstring(from: NSRange(location: offset, length: windowSize))
    }

    private func buildScrollAttributedString() -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        let sepColor = NSColor.secondaryLabelColor
        let result = NSMutableAttributedString()

        let symbols = settings.rotatingSymbols
        for (i, symbol) in symbols.enumerated() {
            let segmentText: String
            let color: NSColor
            if let quote = stockService.quotes.first(where: { $0.symbol == symbol }) {
                segmentText = quote.menuBarText(format: settings.displayFormat, trend: settings.trendStyle, showMarketCap: settings.showMarketCap)
                switch settings.colorMode {
                case .colored: color = quote.isUp ? .systemGreen : .systemRed
                case .grey:    color = .labelColor
                }
            } else {
                segmentText = "\(symbol) ..."
                color = sepColor
            }
            result.append(NSAttributedString(string: segmentText, attributes: [
                .foregroundColor: color,
                .font: font
            ]))
            // Separator after every segment (including last, for a clean wrap-around).
            if i < symbols.count - 1 || symbols.count > 0 {
                result.append(NSAttributedString(string: scrollSeparator, attributes: [
                    .foregroundColor: sepColor,
                    .font: font
                ]))
            }
        }
        return result
    }

    // MARK: - Popover

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else if let button = statusItem.button {
            stockService.fetchQuotes()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)

            // Belt-and-suspenders: close popover on any click outside our app.
            // `.transient` handles most cases but can miss clicks on the desktop.
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.closePopover()
            }
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func openSettings() {
        closePopover()
        UpdateService.shared.checkForUpdates()

        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Tickr Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 500, height: 580))
        window.minSize = NSSize(width: 400, height: 400)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.isReleasedWhenClosed = false
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }
}

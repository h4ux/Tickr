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
            .combineLatest(settings.$rotationInterval, settings.$rotatingSymbols)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in
                self?.restartRotationTimer()
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

    private func updateCurrentDisplay() {
        let symbol = currentDisplaySymbol
        let quote = stockService.quotes.first { $0.symbol == symbol }
        updateMenuBarDisplay(quote)
    }

    private func updateMenuBarDisplay(_ quote: StockQuote?) {
        guard let button = statusItem.button else { return }

        if let quote = quote {
            let text = quote.menuBarText(format: settings.displayFormat, trend: settings.trendStyle)
            let attributed = NSMutableAttributedString(string: text)
            let range = NSRange(location: 0, length: text.count)

            let color: NSColor
            switch settings.colorMode {
            case .colored:
                color = quote.isUp ? .systemGreen : .systemRed
            case .grey:
                color = .labelColor
            }

            attributed.addAttribute(.foregroundColor, value: color, range: range)
            attributed.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), range: range)
            button.attributedTitle = attributed
        } else {
            let symbol = currentDisplaySymbol
            if !symbol.isEmpty {
                let text = "\(symbol) ..."
                let attributed = NSMutableAttributedString(string: text)
                let range = NSRange(location: 0, length: text.count)
                attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: range)
                attributed.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), range: range)
                button.attributedTitle = attributed
            } else {
                button.title = "Tickr"
            }
        }
    }

    // MARK: - Rotation Timer

    private func restartRotationTimer() {
        rotationTimer?.invalidate()
        rotationTimer = nil

        guard settings.rotationEnabled && settings.rotatingSymbols.count > 1 else { return }

        rotationIndex = 0
        let t = Timer(timeInterval: settings.rotationInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.rotationIndex += 1
            self.updateCurrentDisplay()
        }
        RunLoop.main.add(t, forMode: .common)
        rotationTimer = t
    }

    // MARK: - Popover

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            stockService.fetchQuotes()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func openSettings() {
        popover.performClose(nil)

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

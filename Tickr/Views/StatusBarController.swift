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

        // React to quote changes, primary symbol changes, and display setting changes
        stockService.$quotes
            .combineLatest(
                settings.$primarySymbol,
                settings.$displayFormat,
                settings.$trendStyle
            )
            .sink { [weak self] _, _, _, _ in
                self?.updateMenuBarDisplay(self?.stockService.primaryQuote)
            }
            .store(in: &cancellables)

        settings.$colorMode
            .sink { [weak self] _ in
                self?.updateMenuBarDisplay(self?.stockService.primaryQuote)
            }
            .store(in: &cancellables)

        stockService.startFetching()
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
            // Show primary symbol while loading, not the app name
            let symbol = settings.primarySymbol
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

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            // Refresh quotes when opening the dropdown
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

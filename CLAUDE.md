# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Tickr — a macOS menu bar app that displays real-time stock prices. Pure Swift/SwiftUI, no external dependencies. Targets macOS 13.0+.

## Build Commands

```bash
# Build (swiftc, no Xcode required)
./scripts/build_dmg.sh

# Generate app icons from SVG (needs librsvg or ImageMagick)
./scripts/generate_icon.sh

# Type-check only
swiftc -sdk $(xcrun --show-sdk-path --sdk macosx) -target arm64-apple-macos13.0 -typecheck Tickr/*.swift Tickr/**/*.swift
```

Or open `Tickr.xcodeproj` in Xcode and use Cmd+B / Cmd+R.

## Architecture

Menu bar-only app (`LSUIElement = true` — no Dock icon). Uses `NSStatusItem` for the menu bar, `NSPopover` for the dropdown, and a separate `NSWindow` for settings.

- **Models**: `StockData` (quote struct + Yahoo Finance response decoding), `AppSettings` (singleton, UserDefaults-backed, categories, display settings)
- **Services**: `StockService` (Yahoo Finance v8 API, Google Finance for market cap, EarningsWhispers for earnings dates, Yahoo Search for news/sector), `AnalyticsService` (PostHog REST API, opt-out)
- **Views**: `StatusBarController` (owns NSStatusItem + NSPopover), `TickerDropdownView` (categories, expandable stock rows with news/earnings, chart with range tabs), `SettingsView` (display, categories, analytics)

Data flow: `AppSettings` publishes config changes → `StockService` reacts → `StatusBarController` updates menu bar. Market cap, sector, and earnings are fetched in parallel and cached.

## Key Design Decisions

- No API keys required for stock data — Yahoo Finance v8 chart API (public)
- Market cap from Google Finance (requires SOCS consent cookie to bypass consent wall)
- Earnings dates from EarningsWhispers.com (scraped, past dates show as "TBA")
- News from Yahoo Finance search API
- PostHog analytics key stored in `Tickr/Services/Secrets.swift` (git-ignored)
- App Sandbox enabled with network-client-only entitlement
- All network requests HTTPS (ATS enforced)
- Built with `swiftc` directly — no Xcode.app required, just Command Line Tools

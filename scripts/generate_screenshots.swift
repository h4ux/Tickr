#!/usr/bin/env swift

import Cocoa
import CoreGraphics

let projectDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath
let outputDir = "\(projectDir)/screenshots"
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

// MARK: - Drawing helpers

func createImage(width: CGFloat, height: CGFloat, draw: (CGContext, CGFloat, CGFloat) -> Void) -> NSImage {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    if let ctx = NSGraphicsContext.current?.cgContext {
        draw(ctx, width, height)
    }
    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, name: String) {
    guard let tiffData = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiffData),
          let pngData = rep.representation(using: .png, properties: [:]) else { return }
    try? pngData.write(to: URL(fileURLWithPath: "\(outputDir)/\(name).png"))
    print("Generated: \(name).png")
}

func drawText(_ ctx: CGContext, _ text: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .white) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
    ]
    NSAttributedString(string: text, attributes: attrs).draw(at: NSPoint(x: x, y: y))
}

func drawMonoText(_ ctx: CGContext, _ text: String, x: CGFloat, y: CGFloat, size: CGFloat, weight: NSFont.Weight = .medium, color: NSColor = .white) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
    ]
    NSAttributedString(string: text, attributes: attrs).draw(at: NSPoint(x: x, y: y))
}

func drawRoundedRect(_ ctx: CGContext, rect: CGRect, radius: CGFloat, fill: CGColor) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.setFillColor(fill)
    ctx.addPath(path)
    ctx.fillPath()
}

let darkBg = CGColor(red: 0.11, green: 0.11, blue: 0.14, alpha: 1)
let cardBg = CGColor(red: 0.16, green: 0.16, blue: 0.20, alpha: 1)
let greenColor = NSColor(red: 0.2, green: 0.9, blue: 0.5, alpha: 1)
let redColor = NSColor(red: 0.95, green: 0.3, blue: 0.3, alpha: 1)
let dimWhite = NSColor(red: 0.7, green: 0.72, blue: 0.78, alpha: 1)
let accentBlue = NSColor(red: 0.35, green: 0.55, blue: 1.0, alpha: 1)

// MARK: - 1. Menu Bar Screenshot

let menuBar = createImage(width: 700, height: 120) { ctx, w, h in
    // Background
    ctx.setFillColor(CGColor(red: 0.15, green: 0.15, blue: 0.18, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

    // Menu bar strip
    let barY: CGFloat = h - 36
    drawRoundedRect(ctx, rect: CGRect(x: 20, y: barY, width: w - 40, height: 28), radius: 6,
                    fill: CGColor(red: 0.2, green: 0.2, blue: 0.24, alpha: 1))

    // Ticker text in menu bar
    drawMonoText(ctx, "AAPL $255.92 ▲ 0.84%", x: 40, y: barY + 5, size: 13, weight: .medium, color: greenColor)

    // Label
    drawText(ctx, "Menu bar ticker — always visible, color-coded", x: 40, y: 30, size: 13, color: dimWhite)
}
savePNG(menuBar, name: "menubar")

// MARK: - 2. Dropdown Screenshot

let dropdown = createImage(width: 420, height: 520) { ctx, w, h in
    ctx.setFillColor(darkBg)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

    let cardX: CGFloat = 30
    let cardW: CGFloat = w - 60

    // Card background
    drawRoundedRect(ctx, rect: CGRect(x: cardX, y: 30, width: cardW, height: h - 60), radius: 12, fill: cardBg)

    // Header
    drawText(ctx, "Tickr", x: cardX + 16, y: h - 80, size: 16, weight: .bold)
    drawText(ctx, "⟳", x: cardX + cardW - 35, y: h - 80, size: 14, color: accentBlue)

    let lineY = h - 92
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.1))
    ctx.setLineWidth(1)
    ctx.move(to: CGPoint(x: cardX + 12, y: lineY))
    ctx.addLine(to: CGPoint(x: cardX + cardW - 12, y: lineY))
    ctx.strokePath()

    // Single ticker: AAPL
    var y = lineY - 55
    drawMonoText(ctx, "AAPL", x: cardX + 16, y: y + 18, size: 14, weight: .semibold)
    drawText(ctx, "⭐", x: cardX + 62, y: y + 20, size: 9)
    drawText(ctx, "Apple", x: cardX + 16, y: y + 2, size: 11, color: dimWhite)
    drawMonoText(ctx, "$255.92", x: cardX + cardW - 110, y: y + 18, size: 14, weight: .medium)
    drawText(ctx, "↗ +0.84%", x: cardX + cardW - 85, y: y + 2, size: 11, color: greenColor)

    // Single ticker: GOOGL
    y -= 55
    drawMonoText(ctx, "GOOGL", x: cardX + 16, y: y + 18, size: 14, weight: .semibold)
    drawText(ctx, "Alphabet", x: cardX + 16, y: y + 2, size: 11, color: dimWhite)
    drawMonoText(ctx, "$161.36", x: cardX + cardW - 110, y: y + 18, size: 14, weight: .medium)
    drawText(ctx, "↘ -1.22%", x: cardX + cardW - 85, y: y + 2, size: 11, color: redColor)

    // Category header: Tech
    y -= 48
    ctx.setFillColor(CGColor(red: 0.2, green: 0.2, blue: 0.26, alpha: 1))
    ctx.fill(CGRect(x: cardX + 8, y: y - 2, width: cardW - 16, height: 38))

    drawText(ctx, "💻", x: cardX + 16, y: y + 8, size: 14)
    drawText(ctx, "Tech", x: cardX + 38, y: y + 10, size: 14, weight: .semibold)
    drawText(ctx, "3 stocks  +0.52% avg", x: cardX + 38, y: y - 4, size: 10, color: greenColor)
    drawText(ctx, "▼", x: cardX + cardW - 30, y: y + 8, size: 11, color: dimWhite)

    // Expanded category stocks
    y -= 45
    drawMonoText(ctx, "  MSFT", x: cardX + 24, y: y + 14, size: 12, weight: .medium)
    drawText(ctx, "Microsoft", x: cardX + 82, y: y + 14, size: 11, color: dimWhite)
    drawMonoText(ctx, "$381.45", x: cardX + cardW - 100, y: y + 14, size: 12)
    drawText(ctx, "↗ +1.05%", x: cardX + cardW - 85, y: y, size: 10, color: greenColor)

    y -= 36
    drawMonoText(ctx, "  META", x: cardX + 24, y: y + 14, size: 12, weight: .medium)
    drawText(ctx, "Meta Platforms", x: cardX + 82, y: y + 14, size: 11, color: dimWhite)
    drawMonoText(ctx, "$512.20", x: cardX + cardW - 100, y: y + 14, size: 12)
    drawText(ctx, "↗ +0.33%", x: cardX + cardW - 85, y: y, size: 10, color: greenColor)

    y -= 36
    drawMonoText(ctx, "  NVDA", x: cardX + 24, y: y + 14, size: 12, weight: .medium)
    drawText(ctx, "NVIDIA", x: cardX + 82, y: y + 14, size: 11, color: dimWhite)
    drawMonoText(ctx, "$108.14", x: cardX + cardW - 100, y: y + 14, size: 12)
    drawText(ctx, "↗ +0.18%", x: cardX + cardW - 85, y: y, size: 10, color: greenColor)

    // Footer divider
    y -= 20
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.1))
    ctx.move(to: CGPoint(x: cardX + 12, y: y))
    ctx.addLine(to: CGPoint(x: cardX + cardW - 12, y: y))
    ctx.strokePath()

    // Footer
    drawText(ctx, "Updated: 3:42 PM", x: cardX + 16, y: y - 22, size: 10, color: dimWhite)
    drawText(ctx, "Settings…", x: cardX + cardW - 100, y: y - 22, size: 11, color: accentBlue)
    drawText(ctx, "Quit", x: cardX + cardW - 38, y: y - 22, size: 11, color: dimWhite)
}
savePNG(dropdown, name: "dropdown")

// MARK: - 3. Settings Screenshot

let settings = createImage(width: 560, height: 480) { ctx, w, h in
    ctx.setFillColor(darkBg)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

    // Window chrome
    drawRoundedRect(ctx, rect: CGRect(x: 20, y: 20, width: w - 40, height: h - 40), radius: 12, fill: cardBg)

    // Traffic lights
    let tlY = h - 52
    for (i, color) in [CGColor(red: 1, green: 0.38, blue: 0.34, alpha: 1),
                        CGColor(red: 1, green: 0.78, blue: 0.24, alpha: 1),
                        CGColor(red: 0.35, green: 0.78, blue: 0.28, alpha: 1)].enumerated() {
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: CGFloat(40 + i * 22), y: tlY, width: 13, height: 13))
    }

    drawText(ctx, "Tickr Settings", x: 200, y: tlY - 2, size: 16, weight: .bold)

    // Menu Bar Appearance section
    var y = tlY - 42
    drawText(ctx, "MENU BAR APPEARANCE", x: 40, y: y, size: 10, weight: .semibold, color: dimWhite)

    y -= 28
    drawText(ctx, "Display:", x: 50, y: y, size: 13, color: dimWhite)
    drawRoundedRect(ctx, rect: CGRect(x: 220, y: y - 2, width: 200, height: 22), radius: 4,
                    fill: CGColor(red: 0.22, green: 0.22, blue: 0.28, alpha: 1))
    drawText(ctx, "Ticker + Price + Change", x: 228, y: y, size: 12)

    y -= 28
    drawText(ctx, "Color:", x: 50, y: y, size: 13, color: dimWhite)
    drawRoundedRect(ctx, rect: CGRect(x: 220, y: y - 2, width: 200, height: 22), radius: 4,
                    fill: CGColor(red: 0.22, green: 0.22, blue: 0.28, alpha: 1))
    drawText(ctx, "Green / Red", x: 228, y: y, size: 12)

    y -= 28
    drawText(ctx, "Preview:", x: 50, y: y, size: 13, color: dimWhite)
    drawRoundedRect(ctx, rect: CGRect(x: 220, y: y - 4, width: 220, height: 24), radius: 4,
                    fill: CGColor(red: 0.12, green: 0.12, blue: 0.16, alpha: 1))
    drawMonoText(ctx, "AAPL $255.92 ▲ 0.84%", x: 228, y: y - 1, size: 12, color: greenColor)

    // Analytics section
    y -= 44
    drawText(ctx, "ANALYTICS", x: 40, y: y, size: 10, weight: .semibold, color: dimWhite)

    y -= 26
    drawText(ctx, "Help improve Tickr", x: 50, y: y, size: 13, color: dimWhite)
    // Toggle
    drawRoundedRect(ctx, rect: CGRect(x: 220, y: y, width: 36, height: 20), radius: 10,
                    fill: CGColor(red: 0.3, green: 0.75, blue: 0.4, alpha: 1))
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: 238, y: y + 2, width: 16, height: 16))
    // Info button
    drawText(ctx, "ⓘ", x: 264, y: y, size: 14, color: accentBlue)

    // Tickers section
    y -= 44
    drawText(ctx, "TICKERS & CATEGORIES (8/20 symbols)", x: 40, y: y, size: 10, weight: .semibold, color: dimWhite)

    y -= 28
    drawRoundedRect(ctx, rect: CGRect(x: 50, y: y - 2, width: 320, height: 22), radius: 4,
                    fill: CGColor(red: 0.22, green: 0.22, blue: 0.28, alpha: 1))
    drawText(ctx, "Add ticker (e.g. TSLA)", x: 58, y: y, size: 12, color: NSColor(red: 0.5, green: 0.5, blue: 0.55, alpha: 1))
    drawRoundedRect(ctx, rect: CGRect(x: 380, y: y - 2, width: 70, height: 22), radius: 4,
                    fill: CGColor(red: 0.25, green: 0.45, blue: 0.9, alpha: 1))
    drawText(ctx, "Add Ticker", x: 385, y: y, size: 11)
    drawText(ctx, "📁+", x: 458, y: y - 1, size: 14)

    // Ticker list items
    y -= 30
    drawText(ctx, "⭐ AAPL", x: 55, y: y, size: 13, weight: .semibold)
    drawText(ctx, "Apple", x: 130, y: y, size: 12, color: dimWhite)
    drawRoundedRect(ctx, rect: CGRect(x: 390, y: y - 1, width: 60, height: 18), radius: 3,
                    fill: CGColor(red: 0.25, green: 0.35, blue: 0.65, alpha: 0.3))
    drawText(ctx, "Menu Bar", x: 395, y: y, size: 10, color: accentBlue)

    y -= 24
    drawText(ctx, "☆ GOOGL", x: 55, y: y, size: 13)
    drawText(ctx, "Alphabet", x: 138, y: y, size: 12, color: dimWhite)

    y -= 28
    drawText(ctx, "💻 Tech (3)", x: 55, y: y, size: 13, weight: .semibold)
    drawText(ctx, "▶", x: 460, y: y, size: 11, color: dimWhite)
}
savePNG(settings, name: "settings")

// MARK: - 4. Categories Screenshot

let categories = createImage(width: 420, height: 400) { ctx, w, h in
    ctx.setFillColor(darkBg)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

    let cardX: CGFloat = 30
    let cardW: CGFloat = w - 60
    drawRoundedRect(ctx, rect: CGRect(x: cardX, y: 20, width: cardW, height: h - 40), radius: 12, fill: cardBg)

    // Title
    drawText(ctx, "Categories & Tickers", x: cardX + 16, y: h - 58, size: 15, weight: .bold)

    var y = h - 88

    // Category 1: Tech (expanded)
    ctx.setFillColor(CGColor(red: 0.2, green: 0.2, blue: 0.26, alpha: 1))
    ctx.fill(CGRect(x: cardX + 8, y: y - 4, width: cardW - 16, height: 36))
    drawText(ctx, "💻 Tech", x: cardX + 16, y: y + 6, size: 14, weight: .semibold)
    drawText(ctx, "3 stocks  +0.52% avg", x: cardX + 95, y: y + 6, size: 10, color: greenColor)
    drawText(ctx, "▼", x: cardX + cardW - 30, y: y + 6, size: 11, color: dimWhite)

    y -= 32
    drawMonoText(ctx, "  MSFT  Microsoft    $381.45", x: cardX + 20, y: y, size: 11)
    drawText(ctx, "↗ +1.05%", x: cardX + cardW - 82, y: y, size: 10, color: greenColor)

    y -= 24
    drawMonoText(ctx, "  META  Meta         $512.20", x: cardX + 20, y: y, size: 11)
    drawText(ctx, "↗ +0.33%", x: cardX + cardW - 82, y: y, size: 10, color: greenColor)

    y -= 24
    drawMonoText(ctx, "  NVDA  NVIDIA       $108.14", x: cardX + 20, y: y, size: 11)
    drawText(ctx, "↗ +0.18%", x: cardX + cardW - 82, y: y, size: 10, color: greenColor)

    // Category 2: Healthcare (collapsed)
    y -= 38
    ctx.setFillColor(CGColor(red: 0.2, green: 0.2, blue: 0.26, alpha: 1))
    ctx.fill(CGRect(x: cardX + 8, y: y - 4, width: cardW - 16, height: 36))
    drawText(ctx, "🏥 Healthcare", x: cardX + 16, y: y + 6, size: 14, weight: .semibold)
    drawText(ctx, "2 stocks  -0.31% avg", x: cardX + 140, y: y + 6, size: 10, color: redColor)
    drawText(ctx, "▶", x: cardX + cardW - 30, y: y + 6, size: 11, color: dimWhite)

    // Category 3: Energy (collapsed)
    y -= 38
    ctx.setFillColor(CGColor(red: 0.2, green: 0.2, blue: 0.26, alpha: 1))
    ctx.fill(CGRect(x: cardX + 8, y: y - 4, width: cardW - 16, height: 36))
    drawText(ctx, "⚡ Energy", x: cardX + 16, y: y + 6, size: 14, weight: .semibold)
    drawText(ctx, "4 stocks  +1.72% avg", x: cardX + 110, y: y + 6, size: 10, color: greenColor)
    drawText(ctx, "▶", x: cardX + cardW - 30, y: y + 6, size: 11, color: dimWhite)

    // Single ticker below
    y -= 42
    drawMonoText(ctx, "TSLA", x: cardX + 16, y: y + 12, size: 14, weight: .semibold)
    drawText(ctx, "Tesla", x: cardX + 16, y: y - 4, size: 11, color: dimWhite)
    drawMonoText(ctx, "$248.71", x: cardX + cardW - 100, y: y + 12, size: 14)
    drawText(ctx, "↗ +3.41%", x: cardX + cardW - 82, y: y - 4, size: 10, color: greenColor)
}
savePNG(categories, name: "categories")

print("All screenshots generated in: \(outputDir)/")

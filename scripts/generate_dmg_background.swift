#!/usr/bin/env swift

import Cocoa
import CoreGraphics

func generateDMGBackground(projectDir: String) {
    let width: CGFloat = 600
    let height: CGFloat = 400

    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return
    }

    // --- Background gradient ---
    let bgColors: [CGColor] = [
        CGColor(red: 0.06, green: 0.06, blue: 0.12, alpha: 1),
        CGColor(red: 0.10, green: 0.10, blue: 0.20, alpha: 1),
    ]
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors as CFArray, locations: [0, 1]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0), options: [])
    }

    // --- Subtle grid ---
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.03))
    ctx.setLineWidth(0.5)
    for y in stride(from: 80, to: 320, by: 40) {
        ctx.move(to: CGPoint(x: 40, y: CGFloat(y)))
        ctx.addLine(to: CGPoint(x: width - 40, y: CGFloat(y)))
        ctx.strokePath()
    }
    for x in stride(from: 40, to: Int(width) - 40, by: 60) {
        ctx.move(to: CGPoint(x: CGFloat(x), y: 80))
        ctx.addLine(to: CGPoint(x: CGFloat(x), y: 310))
        ctx.strokePath()
    }

    // --- Stock chart (large, across most of the background) ---
    let chartPoints: [(CGFloat, CGFloat)] = [
        (50, 160), (80, 150), (110, 170), (140, 155),
        (170, 180), (200, 165), (225, 190), (250, 200),
        (275, 185), (300, 210), (325, 195), (350, 225),
        (375, 215), (400, 245), (425, 235), (450, 260),
        (475, 250), (500, 275), (525, 265), (550, 290),
    ]

    // Glow fill under chart
    ctx.saveGState()
    let fillPath = CGMutablePath()
    fillPath.move(to: CGPoint(x: chartPoints[0].0, y: 80))
    for p in chartPoints { fillPath.addLine(to: CGPoint(x: p.0, y: p.1)) }
    fillPath.addLine(to: CGPoint(x: chartPoints.last!.0, y: 80))
    fillPath.closeSubpath()
    ctx.addPath(fillPath)
    ctx.clip()
    let glowColors: [CGColor] = [
        CGColor(red: 0, green: 0.8, blue: 0.55, alpha: 0.0),
        CGColor(red: 0, green: 0.8, blue: 0.55, alpha: 0.08),
        CGColor(red: 0, green: 0.8, blue: 0.55, alpha: 0.20),
    ]
    if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glowColors as CFArray, locations: [0, 0.4, 1]) {
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 80), end: CGPoint(x: 0, y: 300), options: [])
    }
    ctx.restoreGState()

    // Chart line with smooth curves
    let linePath = CGMutablePath()
    linePath.move(to: CGPoint(x: chartPoints[0].0, y: chartPoints[0].1))
    for i in 1..<chartPoints.count {
        let prev = chartPoints[i - 1]
        let curr = chartPoints[i]
        let cp1 = CGPoint(x: prev.0 + (curr.0 - prev.0) * 0.4, y: prev.1)
        let cp2 = CGPoint(x: prev.0 + (curr.0 - prev.0) * 0.6, y: curr.1)
        linePath.addCurve(to: CGPoint(x: curr.0, y: curr.1), control1: cp1, control2: cp2)
    }

    // Line glow
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 12, color: CGColor(red: 0, green: 0.9, blue: 0.6, alpha: 0.5))
    ctx.setStrokeColor(CGColor(red: 0.15, green: 0.95, blue: 0.6, alpha: 0.9))
    ctx.setLineWidth(2.5)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(linePath)
    ctx.strokePath()
    ctx.restoreGState()

    // Data point dots (just a few key ones)
    let dotIndices = [0, 5, 10, 15, 19]
    for i in dotIndices {
        let p = chartPoints[i]
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 6, color: CGColor(red: 0, green: 0.9, blue: 0.6, alpha: 0.4))
        ctx.setFillColor(CGColor(red: 0.2, green: 1.0, blue: 0.7, alpha: i == 19 ? 1.0 : 0.5))
        ctx.fillEllipse(in: CGRect(x: p.0 - 3, y: p.1 - 3, width: 6, height: 6))
        ctx.restoreGState()
    }

    // --- Fake ticker labels on the right side ---
    let tickers = [
        ("AAPL", "+1.25%", true),
        ("NVDA", "+3.41%", true),
        ("TSLA", "-0.87%", false),
    ]
    let tickerX: CGFloat = width - 130
    var tickerY: CGFloat = 280
    for (sym, pct, up) in tickers {
        let symAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor(red: 0.7, green: 0.75, blue: 0.85, alpha: 0.4),
        ]
        NSAttributedString(string: sym, attributes: symAttrs).draw(at: NSPoint(x: tickerX, y: tickerY))

        let pctColor = up ? NSColor(red: 0.2, green: 0.9, blue: 0.5, alpha: 0.35) : NSColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 0.35)
        let pctAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: pctColor,
        ]
        NSAttributedString(string: pct, attributes: pctAttrs).draw(at: NSPoint(x: tickerX + 45, y: tickerY))
        tickerY -= 18
    }

    // --- Title "Tickr" ---
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 36, weight: .heavy),
        .foregroundColor: NSColor(red: 0.95, green: 0.97, blue: 1.0, alpha: 0.95),
    ]
    let titleStr = NSAttributedString(string: "Tickr", attributes: titleAttrs)
    let titleSize = titleStr.size()
    titleStr.draw(at: NSPoint(x: (width - titleSize.width) / 2, y: height - 62))

    // --- Tagline ---
    let tagAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        .foregroundColor: NSColor(red: 0.6, green: 0.65, blue: 0.75, alpha: 0.7),
    ]
    let tagStr = NSAttributedString(string: "Stock ticker for your menu bar", attributes: tagAttrs)
    let tagSize = tagStr.size()
    tagStr.draw(at: NSPoint(x: (width - tagSize.width) / 2, y: height - 82))

    // --- Bottom instruction ---
    let subAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12, weight: .regular),
        .foregroundColor: NSColor(red: 0.6, green: 0.65, blue: 0.75, alpha: 0.6),
    ]
    let subStr = NSAttributedString(string: "Drag Tickr to Applications to install", attributes: subAttrs)
    let subSize = subStr.size()
    subStr.draw(at: NSPoint(x: (width - subSize.width) / 2, y: 22))

    // --- Version ---
    let verAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 9, weight: .light),
        .foregroundColor: NSColor(red: 0.45, green: 0.5, blue: 0.6, alpha: 0.4),
    ]
    let verStr = NSAttributedString(string: "v1.0.0", attributes: verAttrs)
    let verSize = verStr.size()
    verStr.draw(at: NSPoint(x: width - verSize.width - 12, y: 8))

    image.unlockFocus()

    guard let tiffData = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiffData),
          let pngData = rep.representation(using: .png, properties: [:]) else {
        print("Failed to generate DMG background")
        return
    }

    let outputDir = "\(projectDir)/build"
    try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
    let outputPath = "\(outputDir)/dmg_background.png"

    do {
        try pngData.write(to: URL(fileURLWithPath: outputPath))
        print("DMG background generated: \(outputPath)")
    } catch {
        print("Error: \(error)")
    }
}

let projectDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath
generateDMGBackground(projectDir: projectDir)

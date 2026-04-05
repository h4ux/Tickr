#!/usr/bin/env swift

import Cocoa
import CoreGraphics

func generateIcon(size: Int) -> NSImage {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let rect = CGRect(x: 0, y: 0, width: s, height: s)
    let scale = s / 1024.0

    // --- Background: dark rounded rect with gradient ---
    let cornerRadius = 220 * scale
    let bgPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let bgColors: [CGColor] = [
        CGColor(red: 0.06, green: 0.06, blue: 0.14, alpha: 1),  // #10102B dark navy
        CGColor(red: 0.09, green: 0.11, blue: 0.22, alpha: 1),  // #171C38
    ]
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors as CFArray, locations: [0, 1]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])
    }

    // --- Subtle grid lines ---
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.04))
    ctx.setLineWidth(1.5 * scale)
    for i in 1...5 {
        let y = s * CGFloat(i) / 6.0
        ctx.move(to: CGPoint(x: 100 * scale, y: y))
        ctx.addLine(to: CGPoint(x: 924 * scale, y: y))
        ctx.strokePath()
    }

    // --- Chart data points (stock going up) ---
    let points: [(CGFloat, CGFloat)] = [
        (120, 720),
        (220, 640),
        (340, 680),
        (430, 560),
        (520, 590),
        (600, 440),
        (700, 380),
        (790, 310),
        (880, 200),
    ]
    let scaledPoints = points.map { CGPoint(x: $0.0 * scale, y: (1024 - $0.1) * scale) }

    // --- Glow/fill area under chart ---
    ctx.saveGState()
    let fillPath = CGMutablePath()
    fillPath.move(to: CGPoint(x: scaledPoints[0].x, y: 150 * scale))
    for p in scaledPoints { fillPath.addLine(to: p) }
    fillPath.addLine(to: CGPoint(x: scaledPoints.last!.x, y: 150 * scale))
    fillPath.closeSubpath()
    ctx.addPath(fillPath)
    ctx.clip()

    let glowColors: [CGColor] = [
        CGColor(red: 0, green: 0.82, blue: 0.63, alpha: 0.0),
        CGColor(red: 0, green: 0.82, blue: 0.63, alpha: 0.18),
        CGColor(red: 0, green: 0.82, blue: 0.63, alpha: 0.35),
    ]
    if let glowGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glowColors as CFArray, locations: [0, 0.5, 1]) {
        ctx.drawLinearGradient(glowGrad, start: CGPoint(x: 0, y: 150 * scale), end: CGPoint(x: 0, y: 850 * scale), options: [])
    }
    ctx.restoreGState()

    // --- Main chart line ---
    let linePath = CGMutablePath()
    linePath.move(to: scaledPoints[0])
    // Smooth curve through points using catmull-rom style
    for i in 0..<scaledPoints.count {
        if i == 0 {
            linePath.move(to: scaledPoints[i])
        } else {
            let prev = scaledPoints[i - 1]
            let curr = scaledPoints[i]
            let cp1 = CGPoint(x: prev.x + (curr.x - prev.x) * 0.4, y: prev.y)
            let cp2 = CGPoint(x: prev.x + (curr.x - prev.x) * 0.6, y: curr.y)
            linePath.addCurve(to: curr, control1: cp1, control2: cp2)
        }
    }

    // Line shadow/glow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 0), blur: 20 * scale, color: CGColor(red: 0, green: 0.9, blue: 0.6, alpha: 0.6))
    ctx.setStrokeColor(CGColor(red: 0, green: 0.85, blue: 0.58, alpha: 1)) // #00D995
    ctx.setLineWidth(32 * scale)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(linePath)
    ctx.strokePath()
    ctx.restoreGState()

    // Bright line on top
    ctx.setStrokeColor(CGColor(red: 0.2, green: 1.0, blue: 0.7, alpha: 1)) // brighter green
    ctx.setLineWidth(12 * scale)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(linePath)
    ctx.strokePath()

    // --- Arrow tip at the end ---
    let lastPt = scaledPoints.last!
    let arrowPath = CGMutablePath()
    arrowPath.move(to: CGPoint(x: lastPt.x + 10 * scale, y: lastPt.y + 40 * scale))
    arrowPath.addLine(to: CGPoint(x: lastPt.x + 50 * scale, y: lastPt.y + 10 * scale))
    arrowPath.addLine(to: CGPoint(x: lastPt.x + 15 * scale, y: lastPt.y - 5 * scale))
    arrowPath.closeSubpath()
    ctx.setFillColor(CGColor(red: 0.2, green: 1.0, blue: 0.7, alpha: 1))
    ctx.addPath(arrowPath)
    ctx.fillPath()

    // --- Data point dots ---
    for (i, p) in scaledPoints.enumerated() {
        let dotSize: CGFloat = (i == scaledPoints.count - 1) ? 16 * scale : 8 * scale
        let dotRect = CGRect(x: p.x - dotSize / 2, y: p.y - dotSize / 2, width: dotSize, height: dotSize)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: i == scaledPoints.count - 1 ? 1.0 : 0.5))
        ctx.fillEllipse(in: dotRect)
    }

    // --- Dollar sign at bottom ---
    let dollarAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 120 * scale, weight: .bold),
        .foregroundColor: NSColor(red: 0.2, green: 1.0, blue: 0.7, alpha: 0.2),
    ]
    let dollarStr = NSAttributedString(string: "$", attributes: dollarAttrs)
    let dollarSize = dollarStr.size()
    dollarStr.draw(at: NSPoint(x: (s - dollarSize.width) / 2, y: 30 * scale))

    ctx.restoreGState()
    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, size: Int, path: String) {
    let targetSize = NSSize(width: size, height: size)
    let newImage = NSImage(size: targetSize)
    newImage.lockFocus()
    image.draw(in: NSRect(origin: .zero, size: targetSize),
               from: NSRect(origin: .zero, size: image.size),
               operation: .copy, fraction: 1.0)
    newImage.unlockFocus()

    guard let tiffData = newImage.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiffData),
          let pngData = rep.representation(using: .png, properties: [:]) else {
        print("Failed to generate PNG for size \(size)")
        return
    }

    do {
        try pngData.write(to: URL(fileURLWithPath: path))
        print("Generated: \(path) (\(size)x\(size))")
    } catch {
        print("Error writing \(path): \(error)")
    }
}

// Main
let projectDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath
let iconDir = "\(projectDir)/Tickr/Assets.xcassets/AppIcon.appiconset"

try? FileManager.default.createDirectory(atPath: iconDir, withIntermediateDirectories: true)

let masterIcon = generateIcon(size: 1024)
let sizes = [16, 32, 64, 128, 256, 512, 1024]

for size in sizes {
    savePNG(masterIcon, size: size, path: "\(iconDir)/icon_\(size).png")
}

print("All icons generated!")

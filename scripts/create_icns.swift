#!/usr/bin/env swift
// Creates an .icns file from the generated PNGs for the app bundle
import Foundation

let projectDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath
let iconsetDir = "\(projectDir)/build/Tickr.iconset"
let pngDir = "\(projectDir)/Tickr/Assets.xcassets/AppIcon.appiconset"
let outputPath = "\(projectDir)/build/Tickr.icns"

try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

// iconutil expects specific filenames
let mappings: [(String, String)] = [
    ("icon_16.png",   "icon_16x16.png"),
    ("icon_32.png",   "icon_16x16@2x.png"),
    ("icon_32.png",   "icon_32x32.png"),
    ("icon_64.png",   "icon_32x32@2x.png"),
    ("icon_128.png",  "icon_128x128.png"),
    ("icon_256.png",  "icon_128x128@2x.png"),
    ("icon_256.png",  "icon_256x256.png"),
    ("icon_512.png",  "icon_256x256@2x.png"),
    ("icon_512.png",  "icon_512x512.png"),
    ("icon_1024.png", "icon_512x512@2x.png"),
]

for (src, dst) in mappings {
    let srcPath = "\(pngDir)/\(src)"
    let dstPath = "\(iconsetDir)/\(dst)"
    try? FileManager.default.removeItem(atPath: dstPath)
    try FileManager.default.copyItem(atPath: srcPath, toPath: dstPath)
}

print("Iconset prepared at: \(iconsetDir)")
print("Run: iconutil -c icns \(iconsetDir) -o \(outputPath)")

#!/usr/bin/env swift

import AppKit
import Foundation

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let buildURL = rootURL.appendingPathComponent("Build", isDirectory: true)
let iconsetURL = buildURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let outputURL = rootURL
    .appendingPathComponent("Packaging", isDirectory: true)
    .appendingPathComponent("AppIcon.icns")

let fileManager = FileManager.default
try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

struct IconSize {
    let filename: String
    let pixels: Int
}

let iconSizes = [
    IconSize(filename: "icon_16x16.png", pixels: 16),
    IconSize(filename: "icon_16x16@2x.png", pixels: 32),
    IconSize(filename: "icon_32x32.png", pixels: 32),
    IconSize(filename: "icon_32x32@2x.png", pixels: 64),
    IconSize(filename: "icon_128x128.png", pixels: 128),
    IconSize(filename: "icon_128x128@2x.png", pixels: 256),
    IconSize(filename: "icon_256x256.png", pixels: 256),
    IconSize(filename: "icon_256x256@2x.png", pixels: 512),
    IconSize(filename: "icon_512x512.png", pixels: 512),
    IconSize(filename: "icon_512x512@2x.png", pixels: 1024)
]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

func rounded(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat, scale: CGFloat) -> NSBezierPath {
    NSBezierPath(
        roundedRect: NSRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale),
        xRadius: radius * scale,
        yRadius: radius * scale
    )
}

func oval(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, scale: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: NSRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale))
}

func drawIcon(pixels: Int) throws -> NSBitmapImageRep {
    let size = CGFloat(pixels)
    let scale = size / 1024
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "AppIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create \(pixels)x\(pixels) bitmap"])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let background = rounded(76, 76, 872, 872, 206, scale: scale)
    let backgroundShadow = NSShadow()
    backgroundShadow.shadowColor = color(0, 0, 0, 0.34)
    backgroundShadow.shadowBlurRadius = 42 * scale
    backgroundShadow.shadowOffset = NSSize(width: 0, height: -12 * scale)
    backgroundShadow.set()
    NSGradient(colors: [
        color(0.24, 0.27, 0.29),
        color(0.12, 0.14, 0.16),
        color(0.07, 0.08, 0.09)
    ])!.draw(in: background, angle: -38)

    NSShadow().set()
    color(1, 1, 1, 0.08).setStroke()
    background.lineWidth = 3 * scale
    background.stroke()

    let body = rounded(174, 320, 676, 394, 82, scale: scale)
    let bodyShadow = NSShadow()
    bodyShadow.shadowColor = color(0, 0, 0, 0.28)
    bodyShadow.shadowBlurRadius = 28 * scale
    bodyShadow.shadowOffset = NSSize(width: 0, height: -8 * scale)
    bodyShadow.set()
    NSGradient(colors: [
        color(0.33, 0.37, 0.39),
        color(0.18, 0.21, 0.23),
        color(0.12, 0.14, 0.16)
    ])!.draw(in: body, angle: 90)

    NSShadow().set()
    color(0.68, 0.73, 0.75, 0.18).setStroke()
    body.lineWidth = 3 * scale
    body.stroke()

    let prism = rounded(340, 668, 250, 92, 42, scale: scale)
    NSGradient(colors: [color(0.36, 0.40, 0.42), color(0.18, 0.21, 0.23)])!.draw(in: prism, angle: 90)

    let grip = rounded(704, 374, 88, 256, 42, scale: scale)
    color(0.09, 0.10, 0.11, 0.48).setFill()
    grip.fill()

    let lensOuter = oval(334, 328, 356, 356, scale: scale)
    color(0.04, 0.05, 0.06, 0.92).setFill()
    lensOuter.fill()

    let lensRing = oval(374, 368, 276, 276, scale: scale)
    NSGradient(colors: [color(0.31, 0.35, 0.38), color(0.12, 0.14, 0.16)])!.draw(in: lensRing, angle: 135)
    color(0.72, 0.78, 0.80, 0.16).setStroke()
    lensRing.lineWidth = 8 * scale
    lensRing.stroke()

    let lensGlass = oval(420, 414, 184, 184, scale: scale)
    NSGradient(colors: [color(0.07, 0.10, 0.12), color(0.02, 0.03, 0.04)])!.draw(in: lensGlass, angle: -45)

    let reflection = oval(462, 520, 76, 38, scale: scale)
    color(0.83, 0.91, 0.94, 0.18).setFill()
    reflection.fill()

    let accent = color(0.95, 0.55, 0.26)
    accent.setStroke()
    let arrow = NSBezierPath()
    arrow.lineWidth = 52 * scale
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 720 * scale, y: 684 * scale))
    arrow.line(to: NSPoint(x: 720 * scale, y: 522 * scale))
    arrow.stroke()

    let arrowHead = NSBezierPath()
    arrowHead.move(to: NSPoint(x: 628 * scale, y: 558 * scale))
    arrowHead.line(to: NSPoint(x: 720 * scale, y: 454 * scale))
    arrowHead.line(to: NSPoint(x: 812 * scale, y: 558 * scale))
    arrowHead.close()
    accent.setFill()
    arrowHead.fill()

    let tray = rounded(392, 288, 256, 34, 17, scale: scale)
    accent.withAlphaComponent(0.9).setFill()
    tray.fill()

    let smallHighlight = rounded(234, 628, 142, 24, 12, scale: scale)
    color(1, 1, 1, 0.13).setFill()
    smallHighlight.fill()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

func writePNG(pixels: Int, filename: String) throws {
    let bitmap = try drawIcon(pixels: pixels)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "AppIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render \(filename)"])
    }
    try data.write(to: iconsetURL.appendingPathComponent(filename), options: .atomic)
}

for size in iconSizes {
    try writePNG(pixels: size.pixels, filename: size.filename)
}

try? fileManager.removeItem(at: outputURL)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: "AppIcon", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
}

print("Wrote \(outputURL.path)")

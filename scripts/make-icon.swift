#!/usr/bin/swift
// Draws the app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift [output.icns] [preview.png]

import AppKit
import CoreGraphics

/// Draws the icon on a 1024-point canvas with the origin in the lower left corner:
/// three clips stacked on a blue plate, the most recent one in front.
func drawIcon(in ctx: CGContext) {
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)
    let space = CGColorSpaceCreateDeviceRGB()

    func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: r, green: g, blue: b, alpha: a)
    }

    func card(_ rect: CGRect, radius: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    // Soft shadow under the plate.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.28))
    ctx.addPath(platePath)
    ctx.setFillColor(color(0.24, 0.30, 0.86))
    ctx.fillPath()
    ctx.restoreGState()

    // The plate, lighter at the top.
    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.clip()
    let blue = CGGradient(
        colorsSpace: space,
        colors: [color(0.40, 0.52, 1.00), color(0.20, 0.24, 0.78)] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(
        blue, start: CGPoint(x: 0, y: plate.maxY), end: CGPoint(x: 0, y: plate.minY), options: [])
    ctx.restoreGState()

    // Two earlier clips, further back and fainter.
    ctx.addPath(card(CGRect(x: 312, y: 664, width: 400, height: 120), radius: 44))
    ctx.setFillColor(color(1, 1, 1, 0.30))
    ctx.fillPath()
    ctx.addPath(card(CGRect(x: 262, y: 566, width: 500, height: 150), radius: 50))
    ctx.setFillColor(color(1, 1, 1, 0.58))
    ctx.fillPath()

    // The most recent clip, in front.
    let front = CGRect(x: 212, y: 236, width: 600, height: 380)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: color(0.05, 0.08, 0.35, 0.45))
    ctx.addPath(card(front, radius: 60))
    ctx.setFillColor(color(1, 1, 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Three lines of copied text.
    ctx.setStrokeColor(color(0.22, 0.27, 0.80, 0.90))
    ctx.setLineWidth(46)
    ctx.setLineCap(.round)
    for (y, endX) in [(CGFloat(520), CGFloat(700)), (CGFloat(426), CGFloat(736)), (CGFloat(332), CGFloat(560))] {
        ctx.move(to: CGPoint(x: 290, y: y))
        ctx.addLine(to: CGPoint(x: endX, y: y))
        ctx.strokePath()
    }
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(in: ctx)
    return rep.representation(using: .png, properties: [:])!
}

let arguments = CommandLine.arguments
let output = arguments.count > 1 ? arguments[1] : "Resources/AppIcon.icns"
let fm = FileManager.default
let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: iconset) }

for (name, pixels) in [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
] {
    try png(pixels: pixels).write(to: iconset.appendingPathComponent("\(name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", output, iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil failed\n".utf8))
    exit(1)
}
print("Wrote \(output)")

if arguments.count > 2 {
    try png(pixels: 512).write(to: URL(fileURLWithPath: arguments[2]))
    print("Wrote \(arguments[2])")
}

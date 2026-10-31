#!/usr/bin/env swift
// Draws the BooxSync app icon: a Mac display with a Boox tablet in front showing a page ("the Boox as a second
// display"). Writes:
//   Resources/AppIcon.icns   (used by scripts/build-app.sh)
//   assets/logo.png          (1024 px, for the README)
// Run from the repository root:  swift scripts/make-icon.swift [palette]
//   palette: graphite (default), indigo, coral, forest
//   swift scripts/make-icon.swift --sheet out.png   renders all palettes side by side instead
import AppKit
import CoreGraphics
import Foundation

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor { CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: 1) }

struct Palette {
    let name: String
    let top: CGColor
    let bottom: CGColor
    let accent: CGColor      // heading line on the Boox page

    /// Tile colour around the Boox (lower right), used as a halo to separate it from the display behind it.
    var halo: CGColor {
        let t: CGFloat = 0.68
        let a = top.components!, b = bottom.components!
        return CGColor(red: a[0] + (b[0] - a[0]) * t, green: a[1] + (b[1] - a[1]) * t, blue: a[2] + (b[2] - a[2]) * t, alpha: 1)
    }
}

let palettes = [
    Palette(name: "indigo", top: rgb(94, 96, 232), bottom: rgb(46, 44, 150), accent: rgb(255, 196, 61)),
    Palette(name: "coral", top: rgb(255, 138, 92), bottom: rgb(214, 62, 86), accent: rgb(255, 226, 120)),
    Palette(name: "graphite", top: rgb(78, 84, 104), bottom: rgb(28, 30, 40), accent: rgb(255, 184, 0)),
    Palette(name: "forest", top: rgb(64, 196, 128), bottom: rgb(14, 100, 80), accent: rgb(255, 214, 90)),
]

let ink = rgb(22, 24, 32)
let paper = rgb(247, 245, 238)
let pageGray = rgb(150, 150, 150)

func round(_ c: CGContext, _ r: CGRect, _ radius: CGFloat, _ fill: CGColor) {
    c.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
    c.setFillColor(fill)
    c.fillPath()
}

/// Draws on a 1024 x 1024 canvas.
func draw(in c: CGContext, palette: Palette) {
    // Icon tile: 824 pt rounded square with the usual margin, gradient, soft shadow.
    let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let body = CGPath(roundedRect: rect, cornerWidth: 186, cornerHeight: 186, transform: nil)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: CGColor(gray: 0, alpha: 0.30))
    c.addPath(body)
    c.setFillColor(palette.bottom)
    c.fillPath()
    c.restoreGState()
    c.saveGState()
    c.addPath(body)
    c.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [palette.top, palette.bottom] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    c.setFillColor(CGColor(gray: 1, alpha: 0.07))
    c.fillEllipse(in: CGRect(x: 40, y: 640, width: 944, height: 520))
    c.restoreGState()
    c.addPath(body)
    c.setStrokeColor(CGColor(gray: 0, alpha: 0.12))
    c.setLineWidth(3)
    c.strokePath()

    // Scale the artwork down and center it so it keeps a comfortable margin inside the tile.
    c.saveGState()
    c.translateBy(x: 512, y: 512)
    c.scaleBy(x: 0.86, y: 0.86)
    c.translateBy(x: -497, y: -466)

    // Mac display (outline) with a stand, behind.
    let mac = CGRect(x: 126, y: 410, width: 490, height: 330)
    c.addPath(CGPath(roundedRect: mac, cornerWidth: 40, cornerHeight: 40, transform: nil))
    c.setStrokeColor(paper)
    c.setLineWidth(34)
    c.strokePath()
    c.setFillColor(paper)
    c.fill(CGRect(x: 326, y: 340, width: 90, height: 60))
    round(c, CGRect(x: 256, y: 316, width: 230, height: 30), 15, paper)

    // Boox in front, lower right, showing a page.
    let boox = CGRect(x: 452, y: 196, width: 410, height: 300)
    round(c, boox.insetBy(dx: -22, dy: -22), 70, palette.halo)
    round(c, boox, 48, ink)
    let display = boox.insetBy(dx: 28, dy: 28)
    round(c, display, 16, paper)
    round(c, CGRect(x: display.minX + 28, y: display.maxY - 50, width: 150, height: 24), 12, palette.accent)
    for (index, width) in [262, 238, 262, 170].enumerated() {
        round(c, CGRect(x: display.minX + 28, y: display.maxY - 92 - CGFloat(index) * 36, width: CGFloat(width), height: 16), 8, pageGray)
    }

    c.restoreGState()
}

func render(size: Int, palette: Palette) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    draw(in: context, palette: palette)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func write(_ rep: NSBitmapImageRep, to path: String) throws {
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let fm = FileManager.default
let arguments = CommandLine.arguments

if let flag = arguments.firstIndex(of: "--sheet"), arguments.count > flag + 1 {
    // Contact sheet: every palette at 520 px, plus 64 and 32 px versions underneath.
    let cell = 520
    let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cell * 2, pixelsHigh: cell * 2 + 140, bitsPerSample: 8, samplesPerPixel: 4,
                                 hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let graphics = NSGraphicsContext(bitmapImageRep: sheet)!
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.setFillColor(CGColor(gray: 0.86, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: cell * 2, height: cell * 2 + 140))
    for (index, palette) in palettes.enumerated() {
        let col = index % 2, row = index / 2
        context.draw(render(size: cell, palette: palette).cgImage!, in: CGRect(x: CGFloat(col * cell), y: CGFloat(cell * (1 - row) + 140), width: CGFloat(cell), height: CGFloat(cell)))
        context.draw(render(size: 64, palette: palette).cgImage!, in: CGRect(x: CGFloat(index * 260 + 30), y: 40, width: 64, height: 64))
        context.draw(render(size: 32, palette: palette).cgImage!, in: CGRect(x: CGFloat(index * 260 + 120), y: 56, width: 32, height: 32))
    }
    NSGraphicsContext.restoreGraphicsState()
    try write(sheet, to: arguments[flag + 1])
    print("wrote \(arguments[flag + 1])")
    exit(0)
}

let chosen = palettes.first { arguments.contains($0.name) } ?? palettes[2]   // graphite by default
let iconset = NSTemporaryDirectory() + "BooxSync.iconset"
try? fm.removeItem(atPath: iconset)
try fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
let variants: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in variants { try write(render(size: size, palette: chosen), to: "\(iconset)/\(name).png") }
try fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)
try fm.createDirectory(atPath: "assets", withIntermediateDirectories: true)
try write(render(size: 1024, palette: chosen), to: "assets/logo.png")

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset, "-o", "Resources/AppIcon.icns"]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "wrote Resources/AppIcon.icns and assets/logo.png (\(chosen.name))" : "iconutil failed")

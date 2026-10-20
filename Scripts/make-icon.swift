// Renders Resources/AppIcon.icns. Run: swift Scripts/make-icon.swift
import AppKit

let canvas: CGFloat = 1024
let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tileRadius: CGFloat = 185

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func drawIcon() {
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: tileRadius, yRadius: tileRadius)

    // Soft drop shadow under the tile, as on other macOS icons.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 24
    shadow.set()
    color(0x2A3FC7).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Everything else is clipped to the tile, so the Dock can slide off its edge.
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()

    NSGradient(colors: [color(0x6FB4FF), color(0x3A62F0), color(0x2A3FC7)],
               atLocations: [0, 0.55, 1], colorSpace: .sRGB)!
        .draw(in: tile, angle: -90)

    // A gentle highlight in the top half.
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.18), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2), angle: -90)

    // The filled window: reaches all the way to the bottom edge.
    let window = NSRect(x: 176, y: 60, width: 672, height: 730)
    NSGraphicsContext.saveGraphicsState()
    let windowShadow = NSShadow()
    windowShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    windowShadow.shadowOffset = NSSize(width: 0, height: -6)
    windowShadow.shadowBlurRadius = 22
    windowShadow.set()
    color(0xFFFFFF, 0.97).setFill()
    NSBezierPath(roundedRect: window, xRadius: 44, yRadius: 44).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Title bar and traffic lights.
    let titleBar = NSRect(x: window.minX, y: window.maxY - 82, width: window.width, height: 82)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: window, xRadius: 44, yRadius: 44).addClip()
    color(0xEEF1F6).setFill()
    titleBar.fill()
    color(0xD9DEE7).setFill()
    NSRect(x: window.minX, y: titleBar.minY - 2, width: window.width, height: 2).fill()
    NSGraphicsContext.restoreGraphicsState()
    for (i, hex) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
        color(UInt32(hex)).setFill()
        NSBezierPath(ovalIn: NSRect(x: window.minX + 40 + CGFloat(i) * 44, y: titleBar.midY - 15, width: 30, height: 30)).fill()
    }

    // Placeholder content lines.
    let lines: [(CGFloat, CGFloat)] = [(0.62, 0x9AA3B5), (0.86, 0xC9CFDA), (0.74, 0xC9CFDA), (0.80, 0xC9CFDA), (0.48, 0xC9CFDA)]
        .map { ($0.0, CGFloat($0.1)) }
    for (i, line) in lines.enumerated() {
        color(UInt32(line.1)).setFill()
        let r = NSRect(x: window.minX + 56, y: titleBar.minY - 72 - CGFloat(i) * 58,
                       width: (window.width - 112) * line.0, height: i == 0 ? 30 : 22)
        NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2).fill()
    }

    // A soft chevron hinting that the Dock is on its way down.
    let chevron = NSBezierPath()
    chevron.move(to: NSPoint(x: 452, y: 262))
    chevron.line(to: NSPoint(x: 512, y: 216))
    chevron.line(to: NSPoint(x: 572, y: 262))
    chevron.lineWidth = 20
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    color(0x3A62F0, 0.35).setStroke()
    chevron.stroke()

    // The Dock, half slid off the bottom edge.
    let dock = NSRect(x: 262, y: 64, width: 500, height: 118)
    NSGraphicsContext.saveGraphicsState()
    let dockShadow = NSShadow()
    dockShadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    dockShadow.shadowOffset = NSSize(width: 0, height: 4)
    dockShadow.shadowBlurRadius = 18
    dockShadow.set()
    color(0xDDE6F7, 0.92).setFill()
    NSBezierPath(roundedRect: dock, xRadius: 36, yRadius: 36).fill()
    NSGraphicsContext.restoreGraphicsState()
    color(0xFFFFFF, 0.9).setStroke()
    let dockStroke = NSBezierPath(roundedRect: dock.insetBy(dx: 1.5, dy: 1.5), xRadius: 35, yRadius: 35)
    dockStroke.lineWidth = 3
    dockStroke.stroke()
    for (i, pair) in [(0xFF9F0A, 0xFF6B00), (0x34C759, 0x1E9E46), (0xFF5E8A, 0xE0335F), (0xA970FF, 0x7A43E6)].enumerated() {
        let r = NSRect(x: dock.minX + 34 + CGFloat(i) * 112, y: dock.minY + 22, width: 82, height: 82)
        NSGradient(starting: color(UInt32(pair.0)), ending: color(UInt32(pair.1)))!
            .draw(in: NSBezierPath(roundedRect: r, xRadius: 20, yRadius: 20), angle: -90)
    }

    NSGraphicsContext.restoreGraphicsState()

    // Thin inner border, like Apple's icon grid.
    color(0xFFFFFF, 0.18).setStroke()
    let border = NSBezierPath(roundedRect: tile.insetBy(dx: 1, dy: 1), xRadius: tileRadius - 1, yRadius: tileRadius - 1)
    border.lineWidth = 2
    border.stroke()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let scale = CGFloat(size) / canvas
    NSGraphicsContext.current?.cgContext.scaleBy(x: scale, y: scale)
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! png(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! png(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! png(size: 1024).write(to: root.appendingPathComponent("Resources/AppIcon-preview.png"))

let out = root.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote \(out.path)" : "iconutil failed")

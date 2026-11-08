// Draws the Keyspace app icon: a 3×3 grid of keycaps (the 9 spaces) on a deep
// indigo squircle, with one glowing key = "the space you're on".
// Usage: swift make_icon.swift out.png
import AppKit

let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// Body (Apple icon grid: 824pt body inside 1024 canvas)
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let drop = NSShadow()
drop.shadowColor = rgb(0, 0, 0, 0.35)
drop.shadowBlurRadius = 30
drop.shadowOffset = NSSize(width: 0, height: -12)
drop.set()
rgb(20, 22, 60).setFill()
bodyPath.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(colors: [rgb(52, 46, 128), rgb(24, 24, 72), rgb(10, 12, 36)],
           atLocations: [0, 0.55, 1], colorSpace: .genericRGB)!.draw(in: bodyPath, angle: -90)

// Soft violet light from the top-left
NSGraphicsContext.saveGraphicsState()
bodyPath.addClip()
NSGradient(colors: [rgb(140, 110, 255, 0.35), rgb(140, 110, 255, 0)])!
    .draw(fromCenter: NSPoint(x: 300, y: 820), radius: 0,
          toCenter: NSPoint(x: 300, y: 820), radius: 620, options: [])
NSGraphicsContext.restoreGraphicsState()

// Hairline rim
rgb(255, 255, 255, 0.10).setStroke()
let rim = NSBezierPath(roundedRect: body.insetBy(dx: 2, dy: 2), xRadius: 183, yRadius: 183)
rim.lineWidth = 4
rim.stroke()

// Keycaps
let key: CGFloat = 168, gap: CGFloat = 40, origin: CGFloat = 220, r: CGFloat = 38
let active = (col: 1, row: 1)   // centre key glows

for row in 0..<3 {
    for col in 0..<3 {
        let x = origin + CGFloat(col) * (key + gap)
        let y = origin + CGFloat(2 - row) * (key + gap)
        let rect = NSRect(x: x, y: y, width: key, height: key)
        let isActive = (col, row) == active

        // Key "side" (depth)
        let side = NSBezierPath(roundedRect: rect.offsetBy(dx: 0, dy: -10), xRadius: r, yRadius: r)
        (isActive ? rgb(60, 40, 150) : rgb(0, 0, 0, 0.40)).setFill()
        side.fill()

        let face = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
        if isActive {
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = rgb(90, 200, 255, 0.85)
            glow.shadowBlurRadius = 70
            glow.set()
            rgb(90, 200, 255).setFill()
            face.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSGradient(colors: [rgb(95, 215, 255), rgb(140, 95, 250)])!.draw(in: face, angle: -45)
        } else {
            NSGradient(colors: [rgb(255, 255, 255, 0.20), rgb(255, 255, 255, 0.07)])!.draw(in: face, angle: -90)
        }

        // Top-edge highlight
        NSGraphicsContext.saveGraphicsState()
        face.addClip()
        rgb(255, 255, 255, isActive ? 0.45 : 0.18).setStroke()
        let hl = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: r - 2, yRadius: r - 2)
        hl.lineWidth = 3
        hl.stroke()
        NSGraphicsContext.restoreGraphicsState()

        // ⌥ glyph on the active key
        if isActive {
            let cfg = NSImage.SymbolConfiguration(pointSize: 84, weight: .bold)
                .applying(.init(paletteColors: [.white]))
            if let sym = NSImage(systemSymbolName: "option", accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg) {
                let s = sym.size
                sym.draw(in: NSRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2,
                                    width: s.width, height: s.height))
            }
        }
    }
}
_ = ctx

img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))

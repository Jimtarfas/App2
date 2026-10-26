// Draws the 1024×1024 Shotfile app icon (no alpha): a screenshot card with lines of text under a magnifier, on teal.
// Usage: swift scripts/make-icon.swift PhoneCleaner/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit

let side = 1024
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

let teal = NSColor(red: 0.06, green: 0.46, blue: 0.43, alpha: 1)
NSGradient(colors: [NSColor(red: 0.04, green: 0.36, blue: 0.34, alpha: 1), NSColor(red: 0.10, green: 0.70, blue: 0.62, alpha: 1)])!
    .draw(in: NSRect(x: 0, y: 0, width: side, height: side), angle: 60)

func shadowed(_ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.3)
    shadow.shadowBlurRadius = 44
    shadow.shadowOffset = NSSize(width: 0, height: -20)
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

// A second screenshot peeking out behind.
NSColor(white: 1, alpha: 0.35).setFill()
NSBezierPath(roundedRect: NSRect(x: 330, y: 200, width: 360, height: 640), xRadius: 56, yRadius: 56).fill()

// The front screenshot, tilted slightly.
let card = NSRect(x: 230, y: 150, width: 380, height: 690)
NSGraphicsContext.saveGraphicsState()
let tilt = NSAffineTransform()
tilt.translateX(by: card.midX, yBy: card.midY)
tilt.rotate(byDegrees: 7)
tilt.translateX(by: -card.midX, yBy: -card.midY)
tilt.concat()
shadowed {
    NSColor.white.setFill()
    NSBezierPath(roundedRect: card, xRadius: 58, yRadius: 58).fill()
}
// Lines of text on the screenshot.
let lineColor = NSColor(red: 0.78, green: 0.85, blue: 0.84, alpha: 1)
NSColor(red: 0.06, green: 0.46, blue: 0.43, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: card.minX + 52, y: card.maxY - 140, width: 200, height: 38), xRadius: 19, yRadius: 19).fill()
for (i, width) in [270.0, 230, 260, 180, 250, 210].enumerated() {
    lineColor.setFill()
    NSBezierPath(roundedRect: NSRect(x: card.minX + 52, y: card.maxY - 230 - CGFloat(i) * 70, width: width, height: 30), xRadius: 15, yRadius: 15).fill()
}
NSGraphicsContext.restoreGraphicsState()

// Magnifier over the lower right.
let lensCenter = NSPoint(x: 640, y: 430)
let lensRadius: CGFloat = 165
shadowed {
    let handle = NSBezierPath()
    handle.move(to: NSPoint(x: lensCenter.x + lensRadius * 0.72, y: lensCenter.y - lensRadius * 0.72))
    handle.line(to: NSPoint(x: lensCenter.x + lensRadius * 1.55, y: lensCenter.y - lensRadius * 1.55))
    handle.lineWidth = 78
    handle.lineCapStyle = .round
    NSColor(red: 1.0, green: 0.72, blue: 0.20, alpha: 1).setStroke()
    handle.stroke()
}
let lens = NSBezierPath(ovalIn: NSRect(x: lensCenter.x - lensRadius, y: lensCenter.y - lensRadius, width: lensRadius * 2, height: lensRadius * 2))
NSColor(white: 1, alpha: 0.88).setFill()
lens.fill()
// Magnified lines of text, with the found word highlighted.
lineColor.setFill()
NSBezierPath(roundedRect: NSRect(x: lensCenter.x - 110, y: lensCenter.y + 50, width: 190, height: 30), xRadius: 15, yRadius: 15).fill()
NSBezierPath(roundedRect: NSRect(x: lensCenter.x - 110, y: lensCenter.y - 80, width: 150, height: 30), xRadius: 15, yRadius: 15).fill()
NSColor(red: 1.0, green: 0.80, blue: 0.30, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: lensCenter.x - 122, y: lensCenter.y - 24, width: 244, height: 50), xRadius: 14, yRadius: 14).fill()
teal.setFill()
NSBezierPath(roundedRect: NSRect(x: lensCenter.x - 100, y: lensCenter.y - 11, width: 120, height: 24), xRadius: 12, yRadius: 12).fill()
NSBezierPath(roundedRect: NSRect(x: lensCenter.x + 32, y: lensCenter.y - 11, width: 68, height: 24), xRadius: 12, yRadius: 12).fill()
lens.lineWidth = 34
NSColor(red: 1.0, green: 0.72, blue: 0.20, alpha: 1).setStroke()
lens.stroke()

let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
CGImageDestinationFinalize(destination)
print("wrote \(output.path)")

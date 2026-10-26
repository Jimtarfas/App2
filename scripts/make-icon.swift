// Draws the 1024×1024 app icon (no alpha): two stacked photo cards with a sparkle on a blue-to-cyan gradient.
// Usage: swift scripts/make-icon.swift PhoneCleaner/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit

let side = 1024
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

let canvas = NSRect(x: 0, y: 0, width: side, height: side)
NSGradient(colors: [NSColor(red: 0.13, green: 0.33, blue: 0.90, alpha: 1),
                    NSColor(red: 0.02, green: 0.70, blue: 0.84, alpha: 1)])!.draw(in: canvas, angle: 50)

func card(_ rect: NSRect, angle: CGFloat, fill: NSColor, shadow: Bool) {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: rect.midX, yBy: rect.midY)
    transform.rotate(byDegrees: angle)
    transform.translateX(by: -rect.midX, yBy: -rect.midY)
    transform.concat()
    if shadow {
        let s = NSShadow()
        s.shadowColor = NSColor(white: 0, alpha: 0.28)
        s.shadowBlurRadius = 40
        s.shadowOffset = NSSize(width: 0, height: -18)
        s.set()
    }
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 64, yRadius: 64).fill()
    NSGraphicsContext.restoreGraphicsState()
}

// Back card, tilted.
card(NSRect(x: 250, y: 250, width: 470, height: 470), angle: 12, fill: NSColor(white: 1, alpha: 0.45), shadow: false)
// Front card.
let front = NSRect(x: 290, y: 215, width: 470, height: 470)
card(front, angle: -6, fill: .white, shadow: true)

// Landscape inside the front card.
NSGraphicsContext.saveGraphicsState()
let transform = NSAffineTransform()
transform.translateX(by: front.midX, yBy: front.midY)
transform.rotate(byDegrees: -6)
transform.translateX(by: -front.midX, yBy: -front.midY)
transform.concat()
let inner = front.insetBy(dx: 44, dy: 44)
NSBezierPath(roundedRect: inner, xRadius: 34, yRadius: 34).addClip()
NSColor(red: 0.86, green: 0.94, blue: 1.0, alpha: 1).setFill()
inner.fill()
let mountains = NSBezierPath()
mountains.move(to: NSPoint(x: inner.minX, y: inner.minY))
mountains.line(to: NSPoint(x: inner.minX, y: inner.minY + 120))
mountains.line(to: NSPoint(x: inner.minX + 130, y: inner.minY + 250))
mountains.line(to: NSPoint(x: inner.minX + 230, y: inner.minY + 150))
mountains.line(to: NSPoint(x: inner.minX + 290, y: inner.minY + 205))
mountains.line(to: NSPoint(x: inner.maxX, y: inner.minY + 60))
mountains.line(to: NSPoint(x: inner.maxX, y: inner.minY))
mountains.close()
NSColor(red: 0.13, green: 0.40, blue: 0.92, alpha: 1).setFill()
mountains.fill()
NSColor(red: 1.0, green: 0.76, blue: 0.20, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: inner.maxX - 130, y: inner.maxY - 130, width: 80, height: 80)).fill()
NSGraphicsContext.restoreGraphicsState()

// Sparkle.
func sparkle(center: NSPoint, radius: CGFloat) {
    let path = NSBezierPath()
    let waist = radius * 0.22
    for i in 0..<8 {
        let angle = CGFloat(i) * .pi / 4 + .pi / 2
        let r = i.isMultiple(of: 2) ? radius : waist
        let point = NSPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
        i == 0 ? path.move(to: point) : path.line(to: point)
    }
    path.close()
    NSColor.white.setFill()
    let s = NSShadow()
    s.shadowColor = NSColor(white: 0, alpha: 0.2)
    s.shadowBlurRadius = 20
    NSGraphicsContext.saveGraphicsState()
    s.set()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
}
sparkle(center: NSPoint(x: 770, y: 760), radius: 120)
sparkle(center: NSPoint(x: 880, y: 600), radius: 52)

let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
CGImageDestinationFinalize(destination)
print("wrote \(output.path)")

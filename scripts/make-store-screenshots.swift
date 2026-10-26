// Renders framed App Store screenshots (no alpha) at 6.9" (1320×2868) and 6.5" (1284×2778).
// Usage: swift scripts/make-store-screenshots.swift marketing/screenshots/raw2 marketing/screenshots
import AppKit

let rawDir = CommandLine.arguments[1], outDir = CommandLine.arguments[2]

// Raw simulator capture, published file name, headline, subheadline — in store order.
let shots = [
    ("01-search-order", "01-search-by-text", "Find Screenshots by Text", "Search any word you remember"),
    ("02-home", "02-sorted", "Every Screenshot, Sorted", "Codes, tickets, receipts and chats"),
    ("03-expired", "03-out-of-date", "Clear What's Out of Date", "Old codes and past tickets, found for you"),
    ("04-open-BOARDING", "04-copy-text", "Copy Text From Screenshots", "Booking codes, addresses, order numbers"),
    ("05-live", "05-live-photos", "Live Photos to Stills", "Keep the photo, drop the motion"),
    ("06-swipe", "06-swipe-review", "Swipe Through Screenshots", "Left to delete, right to keep"),
]
let sizes = [("6.9", 1320, 2868), ("6.5", 1284, 2778)]

func fitted(_ text: String, weight: NSFont.Weight, maxSize: CGFloat, minSize: CGFloat, width: CGFloat, height: CGFloat, color: NSColor) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    paragraph.lineBreakMode = .byWordWrapping
    var size = maxSize
    while true {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let rounded = font.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? font
        let string = NSAttributedString(string: text, attributes: [.font: rounded, .foregroundColor: color, .paragraphStyle: paragraph])
        let bounds = string.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin])
        if bounds.height <= height || size <= minSize { return string }
        size -= 4
    }
}

func render(raw: NSImage, headline: String, subheadline: String, width: Int, height: Int, to output: URL) {
    let scale = CGFloat(width) / 1320
    let W = CGFloat(width), H = CGFloat(height)
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

    NSGradient(colors: [NSColor(red: 0.04, green: 0.33, blue: 0.31, alpha: 1),
                        NSColor(red: 0.08, green: 0.62, blue: 0.55, alpha: 1)])!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -65)

    let titleRect = NSRect(x: 70 * scale, y: H - 440 * scale, width: W - 140 * scale, height: 300 * scale)
    fitted(headline, weight: .heavy, maxSize: 112 * scale, minSize: 72 * scale, width: titleRect.width, height: titleRect.height, color: .white)
        .draw(with: titleRect, options: [.usesLineFragmentOrigin])
    let subtitleRect = NSRect(x: 90 * scale, y: H - 570 * scale, width: W - 180 * scale, height: 120 * scale)
    fitted(subheadline, weight: .medium, maxSize: 54 * scale, minSize: 38 * scale, width: subtitleRect.width, height: subtitleRect.height,
           color: NSColor(white: 1, alpha: 0.85))
        .draw(with: subtitleRect, options: [.usesLineFragmentOrigin])

    let shotWidth = 1010 * scale
    let shotHeight = shotWidth * raw.size.height / raw.size.width
    let shotRect = NSRect(x: (W - shotWidth) / 2, y: H - 640 * scale - shotHeight, width: shotWidth, height: shotHeight)
    let clip = NSBezierPath(roundedRect: shotRect, xRadius: 96 * scale, yRadius: 96 * scale)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
    shadow.shadowBlurRadius = 60 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -20 * scale)
    shadow.set()
    NSColor.black.setFill()
    clip.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    clip.addClip()
    raw.draw(in: shotRect)
    NSGraphicsContext.restoreGraphicsState()
    NSColor(white: 1, alpha: 0.35).setStroke()
    clip.lineWidth = 8 * scale
    clip.stroke()
    NSGraphicsContext.restoreGraphicsState()

    let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
}

for (name, width, height) in sizes {
    let dir = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for shot in shots {
        let raw = NSImage(contentsOfFile: "\(rawDir)/\(shot.0).png")!
        render(raw: raw, headline: shot.2, subheadline: shot.3, width: width, height: height, to: dir.appendingPathComponent(shot.1 + ".png"))
    }
    print("rendered \(name)")
}

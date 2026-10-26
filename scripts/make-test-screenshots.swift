// Draws fictional iPhone screenshots (codes, passes, receipts, chats, directions, notes, posts) for simulator testing
// and App Store screenshots. Every name, brand and number in them is made up.
// Usage: swift scripts/make-test-screenshots.swift <output-dir>
import AppKit
import CoreImage

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let W: CGFloat = 1179, H: CGFloat = 2556
let exif: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy:MM:dd HH:mm:ss"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()

final class Canvas {
    var y: CGFloat = 0   // distance from the top
    let context: CGContext

    init(background: NSColor) {
        context = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        background.setFill()
        NSRect(x: 0, y: 0, width: W, height: H).fill()
        let ink: NSColor = (background.usingColorSpace(.sRGB)?.brightnessComponent ?? 1) < 0.5 ? .white : .black
        text("9:41", size: 50, weight: .semibold, color: ink, x: 140, top: 50)
        ink.setFill()
        for bar in 0..<4 {   // signal bars
            let h = CGFloat(12 + bar * 9)
            NSBezierPath(roundedRect: NSRect(x: W - 300 + CGFloat(bar) * 22, y: H - 105, width: 14, height: h), xRadius: 3, yRadius: 3).fill()
        }
        ink.setStroke()
        let battery = NSBezierPath(roundedRect: NSRect(x: W - 190, y: H - 108, width: 84, height: 40), xRadius: 11, yRadius: 11)
        battery.lineWidth = 3
        battery.stroke()
        NSBezierPath(roundedRect: NSRect(x: W - 184, y: H - 102, width: 72, height: 28), xRadius: 7, yRadius: 7).fill()
        y = 200
    }

    func rect(top: CGFloat, height: CGFloat) -> NSRect { NSRect(x: 0, y: H - top - height, width: W, height: height) }

    @discardableResult
    func text(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .black,
              x: CGFloat = 60, top: CGFloat? = nil, width: CGFloat? = nil, align: NSTextAlignment = .left, mono: Bool = false) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = align
        paragraph.lineSpacing = size * 0.25
        let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
        let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
        let w = width ?? (W - x - 60)
        let bounds = attributed.boundingRect(with: NSSize(width: w, height: 3000), options: [.usesLineFragmentOrigin])
        let t = top ?? y
        attributed.draw(with: NSRect(x: x, y: H - t - bounds.height, width: w, height: bounds.height), options: [.usesLineFragmentOrigin])
        if top == nil { y += bounds.height }
        return bounds.height
    }

    func gap(_ h: CGFloat) { y += h }

    func box(x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat, color: NSColor, radius: CGFloat = 40) {
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: H - top - height, width: width, height: height), xRadius: radius, yRadius: radius).fill()
    }

    func bubble(_ string: String, mine: Bool) {
        let size: CGFloat = 50
        let maxWidth: CGFloat = 760
        let attributed = NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: size)])
        let bounds = attributed.boundingRect(with: NSSize(width: maxWidth, height: 2000), options: [.usesLineFragmentOrigin])
        let bw = bounds.width + 70, bh = bounds.height + 44
        let bx = mine ? W - 50 - bw : 50
        box(x: bx, top: y, width: bw, height: bh, color: mine ? NSColor(red: 0.16, green: 0.47, blue: 1, alpha: 1) : NSColor(white: 0.91, alpha: 1), radius: 44)
        text(string, size: size, color: mine ? .white : .black, x: bx + 35, top: y + 22, width: maxWidth)
        y += bh + 24
    }

    func qr(_ payload: String, x: CGFloat, top: CGFloat, side: CGFloat) {
        let filter = CIFilter(name: "CIQRCodeGenerator", parameters: ["inputMessage": Data(payload.utf8), "inputCorrectionLevel": "M"])!
        let image = filter.outputImage!
        let scale = side / image.extent.width
        let cg = CIContext().createCGImage(image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)), from: CGRect(x: 0, y: 0, width: side, height: side))!
        context.interpolationQuality = .none
        context.draw(cg, in: CGRect(x: x, y: H - top - side, width: side, height: side))
    }

    func save(_ name: String, taken: String) {
        let url = outDir.appendingPathComponent(name + ".PNG")
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "Screenshot", kCGImagePropertyExifDateTimeOriginal: taken],
        ] as CFDictionary)
        CGImageDestinationFinalize(destination)
        print("wrote", name)
    }
}

let blue = NSColor(red: 0.16, green: 0.47, blue: 1, alpha: 1)
let gray = NSColor(white: 0.45, alpha: 1)

func messageThread(_ name: String, sender: String, messages: [(String, Bool)], taken: String) {
    let c = Canvas(background: .white)
    c.text("‹", size: 90, weight: .light, color: blue, x: 40, top: 150)
    c.text(sender, size: 46, weight: .semibold, x: 0, top: 290, width: W, align: .center)
    c.y = 420
    c.text("Today 9:12 AM", size: 36, color: gray, x: 0, width: W, align: .center)
    c.gap(30)
    for (message, mine) in messages { c.bubble(message, mine: mine) }
    c.text("Delivered", size: 34, color: gray, x: W - 260)
    c.save(name, taken: taken)
}

// One-time codes
messageThread("code-northpeak", sender: "Northpeak", messages: [
    ("Your Northpeak verification code is 482913. It expires in 10 minutes. Don't share this code with anyone.", false),
], taken: "2026:10:03 08:41:10")
messageThread("code-brightline", sender: "Brightline Bank", messages: [
    ("Use 7741 to sign in to Brightline. If you didn't try to sign in, ignore this message.", false),
    ("Your one-time passcode is 305 118.", false),
], taken: "2026:09:18 19:05:44")

// Boarding pass (past)
do {
    let c = Canvas(background: NSColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1))
    c.box(x: 60, top: 220, width: W - 120, height: 2050, color: .white)
    c.box(x: 60, top: 220, width: W - 120, height: 260, color: NSColor(red: 0.05, green: 0.22, blue: 0.45, alpha: 1))
    c.text("AVELINE AIR  ·  BOARDING PASS", size: 48, weight: .bold, color: .white, x: 120, top: 320)
    c.y = 560
    c.text("Passenger", size: 38, color: gray, x: 120); c.text("ALEX MORGAN", size: 58, weight: .semibold, x: 120)
    c.gap(40)
    c.text("From                                     To", size: 38, color: gray, x: 120)
    c.text("LIS                    BRU", size: 130, weight: .bold, x: 120)
    c.text("Lisbon                                 Brussels", size: 42, x: 120)
    c.gap(50)
    c.text("Flight  AV 2418      Date  Sep 14, 2026", size: 46, weight: .medium, x: 120)
    c.gap(20)
    c.text("Boarding 06:35      Gate B12      Seat 17C", size: 46, weight: .medium, x: 120)
    c.qr("AV2418-LISBRU-17C-MORGAN", x: (W - 620) / 2, top: c.y + 90, side: 620)
    c.save("pass-flight", taken: "2026:09:13 21:30:00")
}

// Concert ticket (past) and theatre ticket (upcoming)
func ticket(_ name: String, title: String, when: String, seat: String, taken: String) {
    let c = Canvas(background: NSColor(red: 0.10, green: 0.07, blue: 0.20, alpha: 1))
    c.box(x: 60, top: 230, width: W - 120, height: 1950, color: .white)
    c.y = 320
    c.text("ADMIT ONE", size: 44, weight: .heavy, color: NSColor(red: 0.85, green: 0.25, blue: 0.4, alpha: 1), x: 120)
    c.gap(20)
    c.text(title, size: 82, weight: .bold, x: 120)
    c.gap(30)
    c.text(when, size: 50, weight: .medium, x: 120)
    c.text("Doors open 1 hour before", size: 40, color: gray, x: 120)
    c.gap(30)
    c.text(seat, size: 50, weight: .semibold, x: 120)
    c.text("Ticket #TX-58201-44", size: 40, color: gray, x: 120)
    c.qr("TICKET-" + name, x: (W - 600) / 2, top: c.y + 90, side: 600)
    c.save(name, taken: taken)
}
ticket("ticket-concert", title: "Harbor Lights Live", when: "Sat, Aug 22, 2026 · 8:00 PM", seat: "Section 104 · Row F · Seat 9", taken: "2026:08:20 12:14:00")
ticket("ticket-theatre", title: "The Glass Garden", when: "Sat, Dec 12, 2026 · 7:30 PM", seat: "Stalls · Row C · Seat 14", taken: "2026:10:20 18:02:00")

// Receipts
do {
    let c = Canvas(background: .white)
    c.text("✓", size: 120, weight: .bold, color: NSColor(red: 0.1, green: 0.65, blue: 0.35, alpha: 1), x: 0, width: W, align: .center)
    c.text("Order confirmed", size: 70, weight: .bold, x: 0, width: W, align: .center)
    c.text("Order #48213-PL · Placed Oct 2, 2026", size: 40, color: gray, x: 0, width: W, align: .center)
    c.gap(80)
    for (item, price) in [("Wireless earbuds case", "$18.99"), ("USB-C cable (2 m)", "$9.49"), ("Screen protector, 2 pack", "$12.00")] {
        c.text(item, size: 48, x: 90, top: c.y, width: 700); c.text(price, size: 48, x: W - 330, top: c.y, width: 260, align: .right); c.gap(90)
    }
    c.gap(30)
    for (label, value, bold) in [("Subtotal", "$40.48", false), ("Shipping", "$0.00", false), ("Tax", "$3.34", false), ("Total", "$43.82", true)] {
        c.text(label, size: 50, weight: bold ? .bold : .regular, x: 90, top: c.y, width: 600)
        c.text(value, size: 50, weight: bold ? .bold : .regular, x: W - 330, top: c.y, width: 260, align: .right); c.gap(88)
    }
    c.gap(60)
    c.text("Paid with card ending 4242\nArrives Tue, Oct 6", size: 44, color: gray, x: 90)
    c.save("receipt-order", taken: "2026:10:02 14:22:31")
}
do {
    let c = Canvas(background: NSColor(white: 0.97, alpha: 1))
    c.text("Café Lumen", size: 76, weight: .bold, x: 0, width: W, align: .center)
    c.text("Rue des Tanneurs 12 · Receipt", size: 40, color: gray, x: 0, width: W, align: .center)
    c.gap(90)
    for (item, price) in [("Flat white", "€3.80"), ("Almond croissant", "€3.20"), ("Fresh orange juice", "€4.10"), ("Tip", "€1.30")] {
        c.text(item, size: 50, x: 100, top: c.y, width: 700, mono: true); c.text(price, size: 50, x: W - 340, top: c.y, width: 240, align: .right, mono: true); c.gap(90)
    }
    c.gap(40)
    c.text("TOTAL", size: 58, weight: .bold, x: 100, top: c.y, width: 600, mono: true)
    c.text("€12.40", size: 58, weight: .bold, x: W - 340, top: c.y, width: 240, align: .right, mono: true)
    c.gap(120)
    c.text("Paid by card · 16/10/2026 09:48\nThank you!", size: 42, color: gray, x: 0, width: W, align: .center, mono: true)
    c.save("receipt-cafe", taken: "2026:10:16 09:49:02")
}

// Chats
messageThread("chat-sam", sender: "Sam", messages: [
    ("Are we still on for Saturday?", false), ("Yes! 7pm at Marco's?", true), ("Perfect, I'll book a table for four", false),
    ("Can you bring the board game?", false), ("Sure, see you there 🙌", true),
], taken: "2026:07:09 18:30:00")
messageThread("chat-trip", sender: "Lisbon trip 🌞", messages: [
    ("Jules: I found an apartment near Alfama, 4 nights", false), ("Looks great, how much each?", true),
    ("Jules: about 140 per person", false), ("Mia: I'm in!", false), ("Booking it tonight then", true),
], taken: "2026:05:28 22:11:00")

// Directions
do {
    let c = Canvas(background: NSColor(red: 0.90, green: 0.93, blue: 0.88, alpha: 1))
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 200, y: 1100)); path.curve(to: NSPoint(x: 950, y: 2050), controlPoint1: NSPoint(x: 700, y: 1300), controlPoint2: NSPoint(x: 300, y: 1800))
    path.lineWidth = 28; NSColor(red: 0.16, green: 0.47, blue: 1, alpha: 1).setStroke(); path.stroke()
    c.text("Rue de la Loi", size: 38, color: gray, x: 560, top: 900)
    c.text("Parc du Cinquantenaire", size: 38, color: gray, x: 420, top: 1350)
    c.box(x: 0, top: 1700, width: W, height: 860, color: .white, radius: 50)
    c.y = 1780
    c.text("12 min (3.4 km)", size: 76, weight: .bold, x: 80)
    c.text("Fastest route now, the usual traffic", size: 44, color: gray, x: 80)
    c.gap(60)
    c.text("Directions to Atelier Nord, Avenue Louise 210", size: 46, x: 80)
    c.box(x: 80, top: c.y + 60, width: 420, height: 130, color: NSColor(red: 0.1, green: 0.65, blue: 0.35, alpha: 1), radius: 65)
    c.text("Start", size: 54, weight: .bold, color: .white, x: 80, top: c.y + 92, width: 420, align: .center)
    c.save("map-directions", taken: "2026:09:30 08:05:00")
}

// Notes and articles
do {
    let c = Canvas(background: NSColor(red: 1, green: 0.99, blue: 0.94, alpha: 1))
    c.text("Home Wi-Fi", size: 80, weight: .bold)
    c.gap(30)
    c.text("Network: Maplewood-5G\nPassword: sunflower-2041\n\nGuest network: Maplewood-Guest\nPassword: welcome-home-88\n\nRouter admin is on the sticker under the box.", size: 52)
    c.save("note-wifi", taken: "2026:03:12 20:40:00")
}
do {
    let c = Canvas(background: .white)
    c.text("Lemon Garlic Pasta", size: 76, weight: .bold)
    c.text("Serves 2 · 20 minutes", size: 42, color: gray)
    c.gap(40)
    c.text("Ingredients\n• 200 g spaghetti\n• 2 cloves garlic, thinly sliced\n• Zest and juice of 1 lemon\n• 3 tbsp olive oil\n• A handful of parsley\n• Parmesan to serve", size: 48)
    c.gap(40)
    c.text("Method\nCook the pasta in salted water. Meanwhile warm the oil and garlic gently until golden. Add the lemon zest, a splash of pasta water and the drained pasta. Toss with lemon juice, parsley and cheese, and season to taste.", size: 48)
    c.save("note-recipe", taken: "2026:06:02 19:15:00")
}

// Social post with a link
do {
    let c = Canvas(background: .white)
    c.text("@nina.travels", size: 48, weight: .semibold, x: 170)
    c.box(x: 0, top: 330, width: W, height: 1180, color: NSColor(red: 0.95, green: 0.62, blue: 0.38, alpha: 1), radius: 0)
    c.text("Sunset hike ⛰️", size: 90, weight: .heavy, color: .white, x: 0, top: 820, width: W, align: .center)
    c.y = 1560
    c.text("Liked by 128 others", size: 46, weight: .semibold)
    c.text("nina.travels Best trail of the summer. Full guide on my blog: ninatravels.example/sunset-ridge", size: 46)
    c.text("View all 24 comments", size: 44, color: gray)
    c.save("social-post", taken: "2026:08:30 21:02:00")
}

// A screenshot of a picture with almost no text
do {
    let c = Canvas(background: .black)
    NSGradient(colors: [NSColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1), NSColor(red: 0.9, green: 0.4, blue: 0.6, alpha: 1)])!
        .draw(in: NSRect(x: 0, y: 500, width: W, height: 1500), angle: 60)
    c.save("image-wallpaper", taken: "2026:04:18 10:00:00")
}

// More of the everyday kinds, so lists look like a real library.
for (index, (sender, body, taken)) in [
    ("Parcelpoint", "Your parcel locker code is 6620 41. Collect by Friday at the Station Street locker.", "2026:10:21 15:02:00"),
    ("Kitewing", "Kitewing: 993 104 is your login code. It expires in 5 minutes.", "2026:09:02 07:45:00"),
    ("Doctor Office", "Your appointment security code is 4417. Show it at reception.", "2026:08:11 10:20:00"),
].enumerated() {
    messageThread("code-extra-\(index)", sender: sender, messages: [(body, false)], taken: taken)
}
for (index, (shop, lines, total, taken)) in [
    ("Greenline Market", [("Oat milk 1 L", "€2.19"), ("Sourdough loaf", "€3.40"), ("Tomatoes 500 g", "€2.85")], "€8.44", "2026:10:11 18:31:00"),
    ("Northwind Books", [("The Quiet Coast (paperback)", "$16.00"), ("Gift wrap", "$3.00")], "$19.00", "2026:09:24 13:05:00"),
    ("Pixel Repair", [("Battery replacement", "$69.00"), ("Labor", "$20.00")], "$89.00", "2026:07:30 16:44:00"),
].enumerated() {
    let c = Canvas(background: .white)
    c.text(shop, size: 70, weight: .bold, x: 0, width: W, align: .center)
    c.text("Receipt · Order #\(70120 + index * 37)", size: 40, color: gray, x: 0, width: W, align: .center)
    c.gap(90)
    for (item, price) in lines {
        c.text(item, size: 48, x: 90, top: c.y, width: 700); c.text(price, size: 48, x: W - 330, top: c.y, width: 260, align: .right); c.gap(90)
    }
    c.gap(30)
    c.text("Total", size: 54, weight: .bold, x: 90, top: c.y, width: 600)
    c.text(total, size: 54, weight: .bold, x: W - 330, top: c.y, width: 260, align: .right)
    c.gap(110)
    c.text("Paid with card · Thank you for shopping", size: 42, color: gray, x: 90)
    c.save("receipt-extra-\(index)", taken: taken)
}
messageThread("chat-mom", sender: "Mom", messages: [
    ("Did you land ok?", false), ("Yes! Just got my bag", true), ("Call me when you're at the hotel ❤️", false), ("Will do", true),
], taken: "2026:09:14 11:02:00")
messageThread("chat-work", sender: "Priya", messages: [
    ("Can you send the slides before 3?", false), ("On it, 10 more minutes", true), ("Thanks!! 🙏", false),
], taken: "2026:10:08 14:20:00")
do {
    let c = Canvas(background: .white)
    c.text("@coastal.eats", size: 48, weight: .semibold, x: 170)
    c.box(x: 0, top: 330, width: W, height: 1180, color: NSColor(red: 0.30, green: 0.55, blue: 0.45, alpha: 1), radius: 0)
    c.text("Best tacos in town 🌮", size: 84, weight: .heavy, color: .white, x: 0, top: 820, width: W, align: .center)
    c.y = 1560
    c.text("Liked by 2,041 others", size: 46, weight: .semibold)
    c.text("coastal.eats Open until midnight on weekends. Menu: coastaleats.example/menu", size: 46)
    c.text("View all 132 comments", size: 44, color: gray)
    c.save("social-tacos", taken: "2026:07:19 20:15:00")
}
ticket("ticket-train", title: "Riverline Rail · Coach 6", when: "Fri, Oct 9, 2026 · 07:52", seat: "Platform 3 · Seat 41A", taken: "2026:10:08 21:00:00")

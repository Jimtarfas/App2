import CoreML
import Foundation
import os
import Photos
import UIKit
import Vision

/// What a screenshot is mostly about, judged from its text.
enum ShotKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case codes, tickets, receipts, chats, places, links, notes, pictures

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codes: "Codes & Logins"
        case .tickets: "Tickets & Passes"
        case .receipts: "Receipts & Orders"
        case .chats: "Chats"
        case .places: "Maps & Directions"
        case .links: "Posts & Links"
        case .notes: "Notes & Articles"
        case .pictures: "Pictures"
        }
    }

    var symbol: String {
        switch self {
        case .codes: "key.fill"
        case .tickets: "ticket.fill"
        case .receipts: "cart.fill"
        case .chats: "bubble.left.and.bubble.right.fill"
        case .places: "map.fill"
        case .links: "link"
        case .notes: "doc.text.fill"
        case .pictures: "photo.fill"
        }
    }
}

/// What the app learned from one screenshot. Everything stays on the device.
struct ShotInfo: Codable {
    var modified: Double
    var text: String
    var kind: ShotKind
    /// Calendar dates written in the screenshot (a flight date, an event date), as seconds since 1970.
    var dates: [Double]
    var hasBarcode: Bool
}

enum ScreenshotAnalyzer {
    private static let log = Logger(subsystem: "com.cleanupphotos.app", category: "text")

    /// Reads and sorts every screenshot, reusing cached results for ones that haven't changed.
    static func analyze(_ assets: [PHAsset], cache: PersistentCache<ShotInfo>,
                        progress: @escaping @Sendable (Int) -> Void) async -> [String: ShotInfo] {
        var results: [String: ShotInfo] = [:]
        let workers = max(2, min(ProcessInfo.processInfo.activeProcessorCount - 2, 4))
        var next = 0
        var done = 0

        await withTaskGroup(of: (String, ShotInfo?).self) { group in
            func enqueue() {
                guard next < assets.count else { return }
                let asset = assets[next]
                next += 1
                group.addTask {
                    let id = asset.localIdentifier
                    let modified = (asset.modificationDate ?? asset.creationDate)?.timeIntervalSince1970 ?? 0
                    if let cached = cache[id], cached.modified == modified {
                        // Text reading is the slow part; sorting is re-run so rule changes apply to old screenshots too.
                        return (id, sorted(text: cached.text, modified: modified, hasBarcode: cached.hasBarcode))
                    }
                    let fresh = autoreleasepool { read(asset, modified: modified) }
                    if let fresh { cache[id] = fresh }
                    return (id, fresh)
                }
            }
            for _ in 0..<workers { enqueue() }
            while let (id, info) = await group.next() {
                if let info { results[id] = info }
                done += 1
                if done % 5 == 0 || done == assets.count { progress(done) }
                if Task.isCancelled { group.cancelAll(); break }
                enqueue()
            }
        }
        return results
    }

    private static func read(_ asset: PHAsset, modified: Double) -> ShotInfo? {
        guard let image = image(of: asset) else { return nil }
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = true
        let barcodes = VNDetectBarcodesRequest()
        #if targetEnvironment(simulator)
        // The simulator has no Neural Engine; run the text model on the CPU.
        for request in [text, barcodes] as [VNRequest] {
            for (stage, devices) in (try? request.supportedComputeStageDevices) ?? [:] {
                if let cpu = devices.first(where: { if case .cpu = $0 { true } else { false } }) {
                    request.setComputeDevice(cpu, for: stage)
                }
            }
        }
        #endif
        do {
            try VNImageRequestHandler(cgImage: image).perform([text, barcodes])
        } catch {
            log.error("Text recognition failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let lines = withoutStatusBar((text.results ?? []).compactMap { $0.topCandidates(1).first?.string })
        return sorted(text: lines.joined(separator: "\n"), modified: modified, hasBarcode: !(barcodes.results ?? []).isEmpty)
    }

    private static func sorted(text: String, modified: Double, hasBarcode: Bool) -> ShotInfo {
        ShotInfo(modified: modified, text: text, kind: classify(lines: text.components(separatedBy: "\n"), hasBarcode: hasBarcode),
                 dates: calendarDates(in: text).map(\.timeIntervalSince1970), hasBarcode: hasBarcode)
    }

    private static func image(of asset: PHAsset) -> CGImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = false
        var result: CGImage?
        // Tall enough that small UI text stays readable.
        let scale = min(1, 1800 / CGFloat(max(asset.pixelHeight, 1)))
        let size = CGSize(width: CGFloat(asset.pixelWidth) * scale, height: CGFloat(asset.pixelHeight) * scale)
        PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { image, _ in
            result = image?.cgImage
        }
        return result
    }

    // MARK: Sorting

    private static func matches(_ pattern: String, _ text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    /// Scores the text against each kind and picks the strongest; ties go to the more specific kind.
    /// Plain rules, so results are predictable and explainable.
    static func classify(lines rawLines: [String], hasBarcode: Bool) -> ShotKind {
        let lines = withoutStatusBar(rawLines)
        let text = lines.joined(separator: "\n")
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        var scores: [ShotKind: Int] = [:]

        let codeWords = matches(#"\b(verification|verify|passcode|one-time|otp|2fa|security code|login code|sign in|sign-in|code is|your code)\b"#, text)
        let codeDigits = matches(#"\b\d{3}[ -]?\d{3}\b|\b\d{4,8}\b"#, text)
        if codeWords > 0 && codeDigits > 0 { scores[.codes] = 12 + codeWords }

        let ticketWords = matches(#"\b(boarding|gate|seat|flight|ticket|admit|row|section|platform|carriage|coach|check-in|departure|arrival|terminal|booking ref|reservation|pnr)\b"#, text)
        if ticketWords >= 2 || (hasBarcode && ticketWords >= 1) { scores[.tickets] = 4 + ticketWords + (hasBarcode ? 2 : 0) }

        let money = matches(#"[$€£¥₹]\s?\d|\d[.,]\d{2}\s?(€|eur|usd|gbp|\$)"#, text)
        let receiptWords = matches(#"\b(total|subtotal|receipt|order|invoice|paid|payment|tax|vat|amount|shipping|purchase|refund)\b"#, text)
        if money >= 2 && receiptWords >= 1 { scores[.receipts] = 3 + min(money, 5) + receiptWords }

        let travel = matches(#"\b\d+\s?(min|mins|hr|hrs|h)\b"#, text) + matches(#"\b\d+([.,]\d+)?\s?(km|mi|miles)\b"#, text)
        let mapWords = matches(#"\b(directions|route|arrive|eta|navigation|exit|start|traffic|avenue|street|road|rue|via)\b"#, text)
        if travel >= 1 && mapWords >= 1 { scores[.places] = 3 + travel + mapWords }

        let shortLines = lines.filter { $0.count <= 45 }.count
        let chatWords = matches(#"\b(delivered|read \d|imessage|typing|online|last seen|seen \d)\b"#, text)
            + matches(#"\b(today|yesterday)\b[^\n]*\b\d{1,2}:\d{2}\s?(am|pm)\b"#, text)
        if chatWords >= 1 && shortLines >= 3 { scores[.chats] = 3 + chatWords + min(shortLines / 2, 4) }

        let links = matches(#"https?://|www\.|\b[a-z0-9-]+\.(com|net|org|io|app|co|example)(/\S*)?|@[a-z0-9_.]{3,}"#, text)
        let socialWords = matches(#"\b(likes?|liked by|comments?|followers?|follow|repost|retweet|share|views)\b"#, text)
        if links + socialWords >= 2 { scores[.links] = 2 + links + socialWords }

        if words >= 20 { scores[.notes] = 2 + min(words / 40, 4) }

        var best = ShotKind.pictures
        var bestScore = 0
        for kind in ShotKind.allCases {   // most specific first
            if let score = scores[kind], score > bestScore { best = kind; bestScore = score }
        }
        return best
    }

    /// Drops the clock, signal and battery fragments the text reader picks up from the status bar.
    static func withoutStatusBar(_ lines: [String]) -> [String] {
        var lines = lines
        var checked = 0
        while checked < 3, let first = lines.first, lines.count > 1,
              first.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil
                || first.range(of: #"^[•·.\-]\s*\S{0,4}$"#, options: .regularExpression) != nil
                || first.filter(\.isLetter).count <= 2 {
            lines.removeFirst()
            checked += 1
        }
        return lines
    }

    /// Dates written out in the text. Times on their own ("06:35") are ignored because they say nothing about the day.
    static func calendarDates(in text: String) -> [Date] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return [] }
        let dayPattern = try! NSRegularExpression(
            pattern: #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{1,2}|\b\d{1,2}\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)|\b\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}\b|\b\d{4}-\d{2}-\d{2}\b"#,
            options: [.caseInsensitive])
        let range = NSRange(text.startIndex..., in: text)
        var dates = detector.matches(in: text, range: range).compactMap { match -> Date? in
            guard let date = match.date, let swiftRange = Range(match.range, in: text) else { return nil }
            let snippet = String(text[swiftRange])
            return dayPattern.firstMatch(in: snippet, range: NSRange(snippet.startIndex..., in: snippet)) == nil ? nil : date
        }
        // The detector misses some written-out dates next to other numbers ("Flight AV 2418 Date Sep 14, 2026").
        let written = try! NSRegularExpression(
            pattern: #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2}),?\s+(\d{4})\b|\b(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?,?\s+(\d{4})\b"#,
            options: [.caseInsensitive])
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d yyyy"
        let ns = text as NSString
        for match in written.matches(in: text, range: range) {
            func group(_ i: Int) -> String? { match.range(at: i).location == NSNotFound ? nil : ns.substring(with: match.range(at: i)) }
            let parts = group(1) != nil ? (group(1)!, group(2)!, group(3)!) : (group(5)!, group(4)!, group(6)!)
            if let date = formatter.date(from: "\(parts.0.prefix(3).capitalized) \(parts.1) \(parts.2)"),
               !dates.contains(where: { Calendar.current.isDate($0, inSameDayAs: date) }) {
                dates.append(date)
            }
        }
        return dates
    }

    /// One-time codes older than two days, and tickets or passes whose every date has passed.
    static func isExpired(_ info: ShotInfo, created: Date?, now: Date = .now) -> Bool {
        switch info.kind {
        case .codes:
            return (created ?? now) < now.addingTimeInterval(-2 * 86_400)
        case .tickets:
            guard let latest = info.dates.max() else { return false }
            return Date(timeIntervalSince1970: latest) < Calendar.current.startOfDay(for: now)
        default:
            return false
        }
    }
}

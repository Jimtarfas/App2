import Accelerate
import os
import Photos
import UIKit
import Vision

/// What the scanner remembers about one photo: a Vision feature print and a tiny difference hash.
struct Fingerprint: Codable {
    var modified: Double
    var hash: UInt64
    var vector: Data

    var floats: [Float] {
        vector.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}

enum SimilarityScanner {
    private static let log = Logger(subsystem: "com.cleanupphotos.app", category: "scan")

    #if targetEnvironment(simulator)
    static let duplicateThreshold: Float = 0.05
    static let similarThreshold: Float = 0.75
    #else
    /// Feature-print distance (Vision revision 2) below which two photos count as the same picture.
    static let duplicateThreshold: Float = 0.17
    /// Distance below which photos taken close together count as similar shots.
    static let similarThreshold: Float = 0.45
    #endif
    /// Similar shots have to be taken within this many seconds of the previous one in the set.
    static let similarTimeWindow: TimeInterval = 15 * 60

    /// Fingerprints every photo, reusing cached results. Photos that are only in iCloud and have no local preview are skipped.
    static func fingerprints(for assets: [PHAsset], cache: PersistentCache<Fingerprint>,
                             progress: @escaping @Sendable (Int) -> Void) async -> [String: Fingerprint] {
        var results: [String: Fingerprint] = [:]
        results.reserveCapacity(assets.count)
        let workers = max(2, min(ProcessInfo.processInfo.activeProcessorCount - 1, 6))
        var next = 0
        var done = 0

        await withTaskGroup(of: (String, Fingerprint?).self) { group in
            func enqueue() {
                guard next < assets.count else { return }
                let asset = assets[next]
                next += 1
                group.addTask {
                    let id = asset.localIdentifier
                    let modified = (asset.modificationDate ?? asset.creationDate)?.timeIntervalSince1970 ?? 0
                    if let cached = cache[id], cached.modified == modified { return (id, cached) }
                    let fresh = autoreleasepool { fingerprint(of: asset, modified: modified) }
                    if let fresh { cache[id] = fresh }
                    return (id, fresh)
                }
            }
            for _ in 0..<workers { enqueue() }
            while let (id, print) = await group.next() {
                if let print { results[id] = print }
                done += 1
                if done % 20 == 0 || done == assets.count { progress(done) }
                if Task.isCancelled { group.cancelAll(); break }
                enqueue()
            }
        }
        return results
    }

    private static func fingerprint(of asset: PHAsset, modified: Double) -> Fingerprint? {
        guard let image = thumbnail(of: asset) else {
            log.error("No local preview for \(asset.localIdentifier, privacy: .private)")
            return nil
        }
        #if targetEnvironment(simulator)
        return Fingerprint(modified: modified, hash: differenceHash(of: image), vector: pixelVector(of: image))
        #else
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        do {
            try VNImageRequestHandler(cgImage: image).perform([request])
        } catch {
            log.error("Feature print failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        guard let observation = request.results?.first, observation.elementType == .float else { return nil }
        return Fingerprint(modified: modified, hash: differenceHash(of: image), vector: observation.data)
        #endif
    }

    #if targetEnvironment(simulator)
    /// Vision's feature-print model needs the Neural Engine or Metal, and in the simulator it returns the same print
    /// for every image. For testing there, compare mean-centred 16×16 colour thumbnails instead.
    private static func pixelVector(of image: CGImage) -> Data {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        var vector = (0..<(side * side)).flatMap { i in (0..<3).map { Float(pixels[i * 4 + $0]) } }
        let mean = vector.reduce(0, +) / Float(vector.count)
        vector = vector.map { $0 - mean }
        let norm = max(vector.reduce(0) { $0 + $1 * $1 }.squareRoot(), 1e-6)
        return vector.map { $0 / norm }.withUnsafeBufferPointer { Data(buffer: $0) }
    }
    #endif

    private static func thumbnail(of asset: PHAsset) -> CGImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        var result: CGImage?
        let size = CGSize(width: 300, height: 300)
        PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { image, _ in
            result = image?.cgImage
        }
        if result == nil {
            // Fall back to whatever preview is on the device.
            options.deliveryMode = .fastFormat
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { image, _ in
                result = image?.cgImage
            }
        }
        return result
    }

    /// 64-bit dHash: compares neighbouring pixels of a 9×8 grayscale thumbnail.
    private static func differenceHash(of image: CGImage) -> UInt64 {
        var pixels = [UInt8](repeating: 0, count: 9 * 8)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 9, height: 8, bitsPerComponent: 8, bytesPerRow: 9,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 9, height: 8))
        }
        var hash: UInt64 = 0
        for row in 0..<8 {
            for column in 0..<8 {
                hash <<= 1
                if pixels[row * 9 + column] > pixels[row * 9 + column + 1] { hash |= 1 }
            }
        }
        return hash
    }

    static func distance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return .greatestFiniteMagnitude }
        var squared: Float = 0
        vDSP_distancesq(a, 1, b, 1, &squared, vDSP_Length(a.count))
        return squared.squareRoot()
    }

    /// Groups of the same picture saved more than once. `assets` must be sorted oldest first.
    static func duplicateGroups(_ assets: [PHAsset], prints: [String: Fingerprint]) -> [[PHAsset]] {
        let indexed = assets.enumerated().compactMap { index, asset -> (Int, [Float], UInt64)? in
            guard let print = prints[asset.localIdentifier] else { return nil }
            return (index, print.floats, print.hash)
        }
        var parent = Array(0..<assets.count)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        func join(_ a: (Int, [Float], UInt64), _ b: (Int, [Float], UInt64)) {
            guard root(a.0) != root(b.0), sameShape(assets[a.0], assets[b.0]),
                  distance(a.1, b.1) <= duplicateThreshold else { return }
            parent[root(b.0)] = root(a.0)
        }
        // Copies saved at very different times usually still share the exact hash.
        for bucket in Dictionary(grouping: indexed, by: \.2).values where bucket.count > 1 {
            for i in 1..<bucket.count { join(bucket[0], bucket[i]) }
        }
        // Copies saved around the same time (edits, re-downloads, burst duplicates).
        for (position, item) in indexed.enumerated() {
            for other in indexed[(position + 1)..<min(position + 8, indexed.count)] { join(item, other) }
        }
        return Dictionary(grouping: indexed.map(\.0), by: root).values
            .filter { $0.count > 1 }
            .map { $0.sorted().map { assets[$0] } }
    }

    /// Runs of photos taken close together that look alike. `assets` must be sorted oldest first.
    static func similarGroups(_ assets: [PHAsset], prints: [String: Fingerprint]) -> [[PHAsset]] {
        var groups: [[PHAsset]] = []
        var current: [(asset: PHAsset, vector: [Float])] = []
        func close() {
            if current.count > 1 { groups.append(current.map(\.asset)) }
            current.removeAll()
        }
        for asset in assets {
            guard let vector = prints[asset.localIdentifier]?.floats else { continue }
            if let anchor = current.first, let last = current.last {
                let gap = abs((asset.creationDate ?? .distantPast).timeIntervalSince(last.asset.creationDate ?? .distantPast))
                let near = min(distance(anchor.vector, vector), distance(last.vector, vector)) <= similarThreshold
                if gap > similarTimeWindow || !near { close() }
            }
            current.append((asset, vector))
        }
        close()
        return groups
    }

    private static func sameShape(_ a: PHAsset, _ b: PHAsset) -> Bool {
        guard a.pixelHeight > 0, b.pixelHeight > 0 else { return true }
        let ratioA = Double(a.pixelWidth) / Double(a.pixelHeight)
        let ratioB = Double(b.pixelWidth) / Double(b.pixelHeight)
        return abs(ratioA - ratioB) / ratioA < 0.03
    }

    /// The photo we suggest keeping goes first: favorites, then the highest resolution, then the largest file, then the oldest (usually the original).
    static func ranked(_ items: [MediaItem]) -> [MediaItem] {
        items.sorted { a, b in
            if a.asset.isFavorite != b.asset.isFavorite { return a.asset.isFavorite }
            let pixelsA = a.asset.pixelWidth * a.asset.pixelHeight
            let pixelsB = b.asset.pixelWidth * b.asset.pixelHeight
            if pixelsA != pixelsB { return pixelsA > pixelsB }
            if a.bytes != b.bytes { return a.bytes > b.bytes }
            return (a.asset.creationDate ?? .distantPast) < (b.asset.creationDate ?? .distantPast)
        }
    }
}

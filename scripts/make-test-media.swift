// Builds a test photo library from a few source photos: bursts of similar shots, exact duplicates saved later,
// distinct crops as ordinary photos, and large videos. Used for simulator testing and App Store screenshots.
// Usage: swift scripts/make-test-media.swift <source-dir> <output-dir>
import AppKit
import AVFoundation
import CoreImage

let sourceDir = URL(fileURLWithPath: CommandLine.arguments[1])
let outDir = URL(fileURLWithPath: CommandLine.arguments[2])
try? FileManager.default.removeItem(at: outDir)
try! FileManager.default.createDirectory(at: outDir.appendingPathComponent("photos"), withIntermediateDirectories: true)
try! FileManager.default.createDirectory(at: outDir.appendingPathComponent("videos"), withIntermediateDirectories: true)

let context = CIContext()
let sources = try! FileManager.default.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil)
    .filter { ["jpg", "heic"].contains($0.pathExtension.lowercased()) }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
    .map { CIImage(contentsOf: $0, options: [.applyOrientationProperty: true])! }

let exifFormat: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy:MM:dd HH:mm:ss"
    f.locale = Locale(identifier: "en_US_POSIX")
    return f
}()
let base = exifFormat.date(from: "2025:06:14 10:00:00")!
var counter = 0

/// Crops a fraction of the image around a center point (0...1), keeping the aspect ratio.
func crop(_ image: CIImage, zoom: CGFloat, cx: CGFloat = 0.5, cy: CGFloat = 0.5) -> CIImage {
    let e = image.extent
    let w = e.width * zoom, h = e.height * zoom
    let x = min(max(e.minX + e.width * cx - w / 2, e.minX), e.maxX - w)
    let y = min(max(e.minY + e.height * cy - h / 2, e.minY), e.maxY - h)
    return image.cropped(to: CGRect(x: x, y: y, width: w, height: h))
        .transformed(by: CGAffineTransform(translationX: -x, y: -y))
}

func scaled(_ image: CIImage, longSide: CGFloat) -> CIImage {
    let s = longSide / max(image.extent.width, image.extent.height)
    return image.transformed(by: CGAffineTransform(scaleX: s, y: s))
}

func save(_ image: CIImage, date: Date, quality: Double = 0.92) {
    counter += 1
    let url = outDir.appendingPathComponent("photos/IMG_\(String(format: "%04d", 1000 + counter)).JPG")
    let cg = context.createCGImage(image, from: image.extent)!
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)!
    let stamp = exifFormat.string(from: date)
    CGImageDestinationAddImage(destination, cg, [
        kCGImageDestinationLossyCompressionQuality: quality,
        kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: stamp, kCGImagePropertyExifDateTimeDigitized: stamp],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFDateTime: stamp, kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone"],
    ] as CFDictionary)
    CGImageDestinationFinalize(destination)
}

func day(_ n: Double, _ minutes: Double = 0) -> Date { base.addingTimeInterval(n * 86_400 + minutes * 60) }

// Bursts of similar shots: tiny reframing and exposure changes a few seconds apart.
for (index, source) in sources.enumerated() {
    let photo = scaled(source, longSide: 3000)
    let shots = index == 3 ? 3 : 4
    for shot in 0..<shots {
        let zoom = 0.94 - CGFloat(shot) * 0.025
        let frame = crop(photo, zoom: zoom, cx: 0.5 + CGFloat(shot) * 0.012, cy: 0.5 - CGFloat(shot) * 0.008)
            .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: Double(shot % 2) * 0.12 - 0.04])
        save(frame, date: day(Double(index) * 9, Double(shot) * 0.2))
    }
}

// Ordinary photos: distinct framings of each scene on other days.
let framings: [(CGFloat, CGFloat, CGFloat)] = [(0.45, 0.25, 0.3), (0.5, 0.75, 0.7), (0.4, 0.3, 0.75), (0.55, 0.7, 0.25)]
for (index, source) in sources.enumerated() {
    let photo = scaled(source, longSide: 3000)
    for (n, framing) in framings.enumerated() {
        save(crop(photo, zoom: framing.0, cx: framing.1, cy: framing.2), date: day(Double(index) * 9 + Double(n + 2), 300))
    }
}

// Duplicates: the same picture saved again weeks later (a re-download or a copy from a chat).
for (index, source) in sources.enumerated() where index % 2 == 0 {
    let photo = crop(scaled(source, longSide: 3000), zoom: 0.8, cx: 0.4, cy: 0.6)
    save(photo, date: day(Double(index) * 9 + 1, 600))
    save(photo, date: day(Double(index) * 9 + 30, 120), quality: 0.9)
    if index == 0 { save(photo, date: day(70, 45), quality: 0.88) }
}

print("photos:", counter)

// Large videos: slow pans across each scene, encoded at a high bitrate like 4K camera footage.
func makeVideo(from image: CIImage, seconds: Int, name: String) {
    let url = outDir.appendingPathComponent("videos/\(name).mov")
    let size = CGSize(width: 3840, height: 2160)
    let writer = try! AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 45_000_000, AVVideoMaxKeyFrameIntervalKey: 30],
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height,
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    let fps = 30
    let photo = image.transformed(by: CGAffineTransform(scaleX: size.width * 1.25 / image.extent.width, y: size.width * 1.25 / image.extent.width))
    for frame in 0..<(seconds * fps) {
        while !input.isReadyForMoreMediaData { usleep(2000) }
        let t = CGFloat(frame) / CGFloat(seconds * fps)
        let dx = -(photo.extent.width - size.width) * t
        let dy = -(photo.extent.height - size.height) * 0.5
        let shifted = photo.transformed(by: CGAffineTransform(translationX: dx, y: dy))
            .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: sin(Double(frame) / 9) * 0.06])
            .cropped(to: CGRect(origin: .zero, size: size))
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
        context.render(shifted, to: buffer!)
        adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
    }
    input.markAsFinished()
    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    print("video \(name): \(bytes / 1_000_000) MB")
}

makeVideo(from: sources[2], seconds: 24, name: "waterfall")
makeVideo(from: sources[4], seconds: 16, name: "valley")
makeVideo(from: sources[5], seconds: 11, name: "flowers")
makeVideo(from: sources[0], seconds: 7, name: "dunes")
makeVideo(from: sources[1], seconds: 19, name: "leaves")
makeVideo(from: sources[3], seconds: 13, name: "stream")
makeVideo(from: crop(sources[5], zoom: 0.5, cx: 0.3, cy: 0.4), seconds: 9, name: "garden")
makeVideo(from: crop(sources[2], zoom: 0.55, cx: 0.75, cy: 0.6), seconds: 15, name: "falls")
makeVideo(from: crop(sources[4], zoom: 0.5, cx: 0.5, cy: 0.35), seconds: 8, name: "cliffs")

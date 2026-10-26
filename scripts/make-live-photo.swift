// Builds a Live Photo pair (JPEG + MOV sharing a content identifier) from a still image, for simulator testing.
// Usage: swift scripts/make-live-photo.swift <input-image> <output-dir> <name> [exif-date "yyyy:MM:dd HH:mm:ss"]
import AVFoundation
import CoreImage
import Foundation
import ImageIO

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let outDir = URL(fileURLWithPath: CommandLine.arguments[2])
let name = CommandLine.arguments[3]
let taken = CommandLine.arguments.count > 4 ? CommandLine.arguments[4] : "2026:07:04 18:20:00"
let identifier = UUID().uuidString
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// Still: the Apple maker note's key 17 carries the identifier that links it to the video.
let source = CGImageSourceCreateWithURL(input as CFURL, nil)!
let full = CGImageSourceCreateImageAtIndex(source, 0, nil)!
let longSide: CGFloat = 3024
let scale = longSide / CGFloat(max(full.width, full.height))
let ci = CIImage(cgImage: full).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
let still = CIContext().createCGImage(ci, from: ci.extent)!
let jpegURL = outDir.appendingPathComponent(name + ".JPG")
let destination = CGImageDestinationCreateWithURL(jpegURL as CFURL, "public.jpeg" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, still, [
    kCGImagePropertyMakerAppleDictionary: ["17": identifier],
    kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: taken, kCGImagePropertyExifDateTimeDigitized: taken],
    kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone"],
    kCGImageDestinationLossyCompressionQuality: 0.9,
] as CFDictionary)
CGImageDestinationFinalize(destination)

// Video: 3 seconds of slow zoom, with the identifier and a still-image-time marker.
let movURL = outDir.appendingPathComponent(name + ".MOV")
try? FileManager.default.removeItem(at: movURL)
let size = CGSize(width: 1920, height: 1440)
let writer = try! AVAssetWriter(outputURL: movURL, fileType: .mov)
let identifierItem = AVMutableMetadataItem()
identifierItem.key = "com.apple.quicktime.content.identifier" as NSString
identifierItem.keySpace = .quickTimeMetadata
identifierItem.value = identifier as NSString
identifierItem.dataType = "com.apple.metadata.datatype.UTF-8"
writer.metadata = [identifierItem]

let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000],
])
video.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height,
])
writer.add(video)

let spec: NSDictionary = [
    kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier: "mdta/com.apple.quicktime.still-image-time",
    kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType: "com.apple.metadata.datatype.int8",
]
var description: CMFormatDescription?
CMMetadataFormatDescriptionCreateWithMetadataSpecifications(allocator: kCFAllocatorDefault, metadataType: kCMMetadataFormatType_Boxed,
                                                            metadataSpecifications: [spec] as CFArray, formatDescriptionOut: &description)
let metadataInput = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: description)
let metadataAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadataInput)
writer.add(metadataInput)

writer.startWriting()
writer.startSession(atSourceTime: .zero)

let stillTime = AVMutableMetadataItem()
stillTime.key = "com.apple.quicktime.still-image-time" as NSString
stillTime.keySpace = .quickTimeMetadata
stillTime.value = 0 as NSNumber
stillTime.dataType = "com.apple.metadata.datatype.int8"
metadataAdaptor.append(AVTimedMetadataGroup(items: [stillTime], timeRange: CMTimeRange(start: CMTime(value: 15, timescale: 30), duration: CMTime(value: 1, timescale: 30))))
metadataInput.markAsFinished()

let context = CIContext()
let fps = 30
for frame in 0..<(3 * fps) {
    while !video.isReadyForMoreMediaData { usleep(2000) }
    let zoom = 1 + CGFloat(frame) / CGFloat(3 * fps) * 0.06
    let s = max(size.width / ci.extent.width, size.height / ci.extent.height) * zoom
    let scaled = ci.transformed(by: CGAffineTransform(scaleX: s, y: s))
    let framed = scaled.transformed(by: CGAffineTransform(translationX: -(scaled.extent.width - size.width) / 2, y: -(scaled.extent.height - size.height) / 2))
        .cropped(to: CGRect(origin: .zero, size: size))
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
    context.render(framed, to: buffer!)
    adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
}
video.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
print(writer.status == .completed ? "wrote \(name) (\(identifier))" : "failed: \(String(describing: writer.error))")

import Photos

/// One photo or video in the library, with the space it takes on the device.
struct MediaItem: Identifiable, Hashable {
    let asset: PHAsset
    let bytes: Int64

    var id: String { asset.localIdentifier }
    var isVideo: Bool { asset.mediaType == .video }

    static func == (lhs: MediaItem, rhs: MediaItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Duplicate or similar photos. The first item is the one we suggest keeping.
struct MediaGroup: Identifiable, Hashable {
    let id: String
    var items: [MediaItem]

    var best: MediaItem { items[0] }
    var extras: ArraySlice<MediaItem> { items.dropFirst() }
    var reclaimableBytes: Int64 { extras.reduce(0) { $0 + $1.bytes } }
    var date: Date? { items.compactMap(\.asset.creationDate).max() }
}

enum GroupKind: String, Hashable {
    case duplicates, similar
}

enum MediaKind: String, Hashable {
    case screenshots, videos
}

extension Int64 {
    /// "1.2 GB", "340 MB"
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension Sequence where Element == MediaItem {
    var totalBytes: Int64 { reduce(0) { $0 + $1.bytes } }
}

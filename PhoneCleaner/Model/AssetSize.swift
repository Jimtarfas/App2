import Photos

enum AssetSize {
    /// Bytes the asset takes on the device: the original plus any edited version or Live Photo video.
    static func bytes(of asset: PHAsset) -> Int64 {
        var total: Int64 = 0
        for resource in PHAssetResource.assetResources(for: asset) where resource.responds(to: Selector(("fileSize"))) {
            if let size = resource.value(forKey: "fileSize") as? NSNumber {
                total += size.int64Value
            }
        }
        return total > 0 ? total : estimate(for: asset)
    }

    /// Rough size for assets whose resources don't report one.
    private static func estimate(for asset: PHAsset) -> Int64 {
        if asset.mediaType == .video {
            return Int64(max(asset.duration, 1) * 1_500_000)
        }
        return Int64(Double(asset.pixelWidth * asset.pixelHeight) * 0.3)
    }
}

struct DeviceStorage: Equatable {
    var total: Int64
    var available: Int64

    var used: Int64 { max(total - available, 0) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func current() -> DeviceStorage {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        return DeviceStorage(total: Int64(values?.volumeTotalCapacity ?? 0),
                             available: values?.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}

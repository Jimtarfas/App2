import Photos

/// Turns Live Photos into still photos. The still keeps the picture (including any edit), date, location,
/// favorite flag and album membership; only the short video that makes the photo "live" is dropped.
enum LivePhotoConverter {
    struct Prepared {
        let original: PHAsset
        let file: URL
        let filename: String
        let albums: [PHAssetCollection]
    }

    /// Bytes taken by the video part of a Live Photo, which is what converting it saves.
    static func videoBytes(of asset: PHAsset) -> Int64 {
        PHAssetResource.assetResources(for: asset)
            .filter { $0.type == .pairedVideo || $0.type == .fullSizePairedVideo }
            .reduce(0) { total, resource in
                guard resource.responds(to: Selector(("fileSize"))), let size = resource.value(forKey: "fileSize") as? NSNumber else { return total }
                return total + size.int64Value
            }
    }

    /// Copies each Live Photo's still image to a temporary file, ready to be added back as a plain photo.
    static func prepare(_ assets: [PHAsset]) async throws -> [Prepared] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("live-to-still-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var prepared: [Prepared] = []
        for asset in assets {
            let resources = PHAssetResource.assetResources(for: asset)
            // An edited photo has a rendered full-size version; keep what the person sees.
            guard let still = resources.first(where: { $0.type == .fullSizePhoto }) ?? resources.first(where: { $0.type == .photo }) else { continue }
            let file = folder.appendingPathComponent(UUID().uuidString + "-" + still.originalFilename)
            let options = PHAssetResourceRequestOptions()
            options.isNetworkAccessAllowed = true
            try await PHAssetResourceManager.default().writeData(for: still, toFile: file, options: options)
            let albums = PHAssetCollection.fetchAssetCollectionsContaining(asset, with: .album, options: nil)
            var editable: [PHAssetCollection] = []
            albums.enumerateObjects { album, _, _ in
                if album.canPerform(.addContent) { editable.append(album) }
            }
            prepared.append(Prepared(original: asset, file: file, filename: still.originalFilename, albums: editable))
        }
        return prepared
    }

    /// Adds the stills and deletes the Live Photos in one change, so either both happen or neither does.
    /// iOS asks the person to confirm the deletion.
    static func commit(_ prepared: [Prepared]) async throws {
        try await PHPhotoLibrary.shared().performChanges {
            for item in prepared {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = item.filename
                request.addResource(with: .photo, fileURL: item.file, options: options)
                request.creationDate = item.original.creationDate
                request.location = item.original.location
                request.isFavorite = item.original.isFavorite
                request.isHidden = item.original.isHidden
                if let placeholder = request.placeholderForCreatedAsset {
                    for album in item.albums {
                        PHAssetCollectionChangeRequest(for: album)?.addAssets([placeholder] as NSArray)
                    }
                }
            }
            PHAssetChangeRequest.deleteAssets(prepared.map(\.original) as NSArray)
        }
    }

    static func cleanUp(_ prepared: [Prepared]) {
        for folder in Set(prepared.map { $0.file.deletingLastPathComponent() }) {
            try? FileManager.default.removeItem(at: folder)
        }
    }
}

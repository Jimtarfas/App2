import Observation
import Photos
import PhotosUI
import UIKit

/// The photo library as the app sees it: access, what the scans found, and the changes the person makes.
@MainActor
@Observable
final class Cleaner {
    enum ScanState: Equatable {
        case idle
        case listing
        case analyzing(done: Int, total: Int)
        case finished
    }

    private(set) var authorization = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    /// Reading the text in screenshots.
    private(set) var textState = ScanState.idle
    /// Looking for duplicate and similar photos.
    private(set) var scanState = ScanState.idle
    private(set) var screenshots: [MediaItem] = []
    private(set) var shotInfo: [String: ShotInfo] = [:]
    private(set) var duplicates: [MediaGroup] = []
    private(set) var similar: [MediaGroup] = []
    /// Live Photos; `bytes` is the space converting each one to a still would save.
    private(set) var livePhotos: [MediaItem] = []
    private(set) var largeVideos: [MediaItem] = []
    private(set) var photoCount = 0
    private(set) var videoCount = 0
    private(set) var storage = DeviceStorage.current()
    private(set) var freedBytes: Int64
    private(set) var freedItems: Int
    private(set) var freeActionsLeft: Int
    private(set) var keptIDs: Set<String>

    /// Free plan: this many deletions or conversions per calendar day.
    static let freeActionsPerDay = 20
    /// Videos at least this big show up under Large Videos.
    static let largeVideoBytes: Int64 = 10_000_000

    private let fingerprints = PersistentCache<Fingerprint>(name: "fingerprints-v2")
    private let texts = PersistentCache<ShotInfo>(name: "screenshot-text-v1")
    private var scanTask: Task<Void, Never>?
    private let defaults = UserDefaults.standard

    init() {
        freedBytes = Int64(defaults.integer(forKey: "freedBytes"))
        freedItems = defaults.integer(forKey: "freedItems")
        freeActionsLeft = Self.freeActionsPerDay
        keptIDs = KeptPhotos.shared.ids
        refreshAllowance()
    }

    var hasAccess: Bool { authorization == .authorized || authorization == .limited }
    var isLimited: Bool { authorization == .limited }
    var listsReady: Bool { scanState != .idle && scanState != .listing }
    var textReady: Bool { textState == .finished }
    var groupsReady: Bool { scanState == .finished }

    // MARK: Screenshots

    func shots(_ kind: ShotKind) -> [MediaItem] {
        screenshots.filter { shotInfo[$0.id]?.kind == kind }
    }

    /// One-time codes and past tickets the person hasn't chosen to keep.
    var expiredShots: [MediaItem] {
        screenshots.filter { item in
            guard !keptIDs.contains(item.id), let info = shotInfo[item.id] else { return false }
            return ScreenshotAnalyzer.isExpired(info, created: item.asset.creationDate)
        }
    }

    func text(of item: MediaItem) -> String? { shotInfo[item.id]?.text }

    /// Screenshots whose text contains every word of the query, ignoring case and accents.
    func search(_ query: String) -> [MediaItem] {
        let terms = query.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !terms.isEmpty else { return [] }
        return screenshots.filter { item in
            guard let text = shotInfo[item.id]?.text else { return false }
            return terms.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    func keep(_ item: MediaItem) {
        KeptPhotos.shared.insert(item.id)
        keptIDs.insert(item.id)
    }

    // MARK: Access

    func requestAccess() async {
        authorization = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        if hasAccess { scan() }
    }

    /// Call when the app comes back to the foreground.
    func refresh() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let changed = status != authorization
        authorization = status
        storage = .current()
        refreshAllowance()
        keptIDs = KeptPhotos.shared.ids
        if hasAccess && (changed || scanState == .idle) { scan() }
    }

    func presentLimitedPicker() {
        guard let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }

    // MARK: Scanning

    func scan() {
        guard hasAccess else { return }
        scanTask?.cancel()
        scanTask = Task { await runScan() }
    }

    private func runScan() async {
        scanState = .listing
        textState = .listing
        let fingerprints = self.fingerprints
        let texts = self.texts
        let library = await Task.detached(priority: .userInitiated) { LibrarySnapshot.load() }.value
        guard !Task.isCancelled else { return }

        photoCount = library.photos.count + library.screenshots.count
        videoCount = library.videos.count
        screenshots = library.screenshots
        livePhotos = library.livePhotos
        largeVideos = library.videos.filter { $0.bytes >= Self.largeVideoBytes }
        storage = .current()

        // Screenshots first: reading them is what the app is for.
        let shotAssets = library.screenshots.map(\.asset)
        textState = .analyzing(done: 0, total: shotAssets.count)
        let info = await ScreenshotAnalyzer.analyze(shotAssets, cache: texts) { done in
            Task { @MainActor [weak self] in
                guard let self, case .analyzing(let current, let total) = self.textState, done > current else { return }
                self.textState = .analyzing(done: done, total: total)
            }
        }
        guard !Task.isCancelled else { return }
        shotInfo = info
        textState = .finished
        Task.detached(priority: .utility) { texts.save(keeping: Set(shotAssets.map(\.localIdentifier))) }

        let photos = library.photos
        scanState = .analyzing(done: 0, total: photos.count)
        let prints = await SimilarityScanner.fingerprints(for: photos, cache: fingerprints) { done in
            Task { @MainActor [weak self] in
                guard let self, case .analyzing(let current, let total) = self.scanState, done > current else { return }
                self.scanState = .analyzing(done: done, total: total)
            }
        }
        guard !Task.isCancelled else { return }

        let groups = await Task.detached(priority: .userInitiated) {
            let duplicateSets = SimilarityScanner.duplicateGroups(photos, prints: prints)
            let duplicateIDs = duplicateSets.map { Set($0.map(\.localIdentifier)) }
            // A run of similar shots that is just one set of duplicates is already covered under Duplicates.
            let similarSets = SimilarityScanner.similarGroups(photos, prints: prints).filter { set in
                let ids = Set(set.map(\.localIdentifier))
                return !duplicateIDs.contains { ids.isSubset(of: $0) }
            }
            fingerprints.save(keeping: Set(photos.map(\.localIdentifier)))
            return (Self.mediaGroups(duplicateSets), Self.mediaGroups(similarSets))
        }.value
        guard !Task.isCancelled else { return }

        duplicates = groups.0
        similar = groups.1
        scanState = .finished
    }

    nonisolated private static func mediaGroups(_ sets: [[PHAsset]]) -> [MediaGroup] {
        sets.map { set in
            let items = SimilarityScanner.ranked(set.map { MediaItem(asset: $0, bytes: AssetSize.bytes(of: $0)) })
            return MediaGroup(id: items[0].id, items: items)
        }
        .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }

    // MARK: Changing the library

    /// Whether the free plan still covers `count` more deletions or conversions today.
    func freePlanAllows(_ count: Int) -> Bool {
        refreshAllowance()
        return count <= freeActionsLeft
    }

    /// Asks Photos to delete the items. Photos shows its own confirmation, and deleted items stay in Recently Deleted for 30 days.
    /// Returns the bytes removed from the library, or nil if the person cancelled.
    func delete(_ items: [MediaItem], countsAgainstFreePlan: Bool) async throws -> Int64? {
        guard !items.isEmpty else { return 0 }
        let assets = items.map(\.asset) as NSArray
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            }
        } catch let error as NSError where Self.isCancellation(error) {
            return nil
        }
        let bytes = items.totalBytes
        remove(Set(items.map(\.id)))
        record(bytes: bytes, items: items.count, countsAgainstFreePlan: countsAgainstFreePlan)
        return bytes
    }

    /// Replaces Live Photos with still photos. Returns the bytes saved, or nil if the person cancelled.
    func convertToStills(_ items: [MediaItem], countsAgainstFreePlan: Bool) async throws -> Int64? {
        guard !items.isEmpty else { return 0 }
        let prepared = try await LivePhotoConverter.prepare(items.map(\.asset))
        defer { LivePhotoConverter.cleanUp(prepared) }
        do {
            try await LivePhotoConverter.commit(prepared)
        } catch let error as NSError where Self.isCancellation(error) {
            return nil
        }
        let converted = Set(prepared.map(\.original.localIdentifier))
        let bytes = items.filter { converted.contains($0.id) }.totalBytes
        livePhotos.removeAll { converted.contains($0.id) }
        record(bytes: bytes, items: 0, countsAgainstFreePlan: countsAgainstFreePlan, actions: converted.count)
        // The stills are new photos; pick them up for duplicate checks.
        scan()
        return bytes
    }

    private static func isCancellation(_ error: NSError) -> Bool {
        error.domain == PHPhotosErrorDomain && error.code == PHPhotosError.Code.userCancelled.rawValue
    }

    private func record(bytes: Int64, items: Int, countsAgainstFreePlan: Bool, actions: Int? = nil) {
        freedBytes += bytes
        freedItems += items
        defaults.set(Int(freedBytes), forKey: "freedBytes")
        defaults.set(freedItems, forKey: "freedItems")
        if countsAgainstFreePlan { useFreeActions(actions ?? items) }
        storage = .current()
    }

    private func remove(_ ids: Set<String>) {
        func prune(_ groups: [MediaGroup]) -> [MediaGroup] {
            groups.compactMap { group in
                var group = group
                group.items.removeAll { ids.contains($0.id) }
                return group.items.count > 1 ? group : nil
            }
        }
        duplicates = prune(duplicates)
        similar = prune(similar)
        screenshots.removeAll { ids.contains($0.id) }
        livePhotos.removeAll { ids.contains($0.id) }
        largeVideos.removeAll { ids.contains($0.id) }
        photoCount = PHAsset.fetchAssets(with: .image, options: nil).count
        videoCount = PHAsset.fetchAssets(with: .video, options: nil).count
    }

    // MARK: Free plan allowance

    private var today: String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        return "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    private func refreshAllowance() {
        let used = defaults.string(forKey: "freeDeletesDay") == today ? defaults.integer(forKey: "freeDeletesUsed") : 0
        freeActionsLeft = max(Self.freeActionsPerDay - used, 0)
    }

    private func useFreeActions(_ count: Int) {
        let used = defaults.string(forKey: "freeDeletesDay") == today ? defaults.integer(forKey: "freeDeletesUsed") : 0
        defaults.set(today, forKey: "freeDeletesDay")
        defaults.set(used + count, forKey: "freeDeletesUsed")
        refreshAllowance()
    }
}

/// Everything the scan needs from Photos, fetched off the main thread.
private struct LibrarySnapshot {
    var photos: [PHAsset] = []
    var screenshots: [MediaItem] = []
    var livePhotos: [MediaItem] = []
    var videos: [MediaItem] = []

    static func load() -> LibrarySnapshot {
        var snapshot = LibrarySnapshot()
        let oldestFirst = PHFetchOptions()
        oldestFirst.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        PHAsset.fetchAssets(with: .image, options: oldestFirst).enumerateObjects { asset, _, _ in
            if asset.mediaSubtypes.contains(.photoScreenshot) {
                snapshot.screenshots.append(MediaItem(asset: asset, bytes: AssetSize.bytes(of: asset)))
                return
            }
            snapshot.photos.append(asset)
            if asset.mediaSubtypes.contains(.photoLive) {
                let saving = LivePhotoConverter.videoBytes(of: asset)
                if saving > 0 { snapshot.livePhotos.append(MediaItem(asset: asset, bytes: saving)) }
            }
        }
        snapshot.screenshots.reverse()
        snapshot.livePhotos.reverse()

        PHAsset.fetchAssets(with: .video, options: oldestFirst).enumerateObjects { asset, _, _ in
            snapshot.videos.append(MediaItem(asset: asset, bytes: AssetSize.bytes(of: asset)))
        }
        snapshot.videos.sort { $0.bytes > $1.bytes }
        return snapshot
    }
}

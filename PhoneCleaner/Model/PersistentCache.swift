import Foundation

/// A small on-disk dictionary in Caches, keyed by photo identifier, so rescans only analyze new or edited photos.
final class PersistentCache<Value: Codable>: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var entries: [String: Value]

    init(name: String) {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        url = caches.appendingPathComponent(name + ".plist")
        if let data = try? Data(contentsOf: url),
           let decoded = try? PropertyListDecoder().decode([String: Value].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    subscript(id: String) -> Value? {
        get { lock.withLock { entries[id] } }
        set { lock.withLock { entries[id] = newValue } }
    }

    /// Writes the cache, dropping photos that are no longer in the library.
    func save(keeping ids: Set<String>) {
        let snapshot = lock.withLock {
            entries = entries.filter { ids.contains($0.key) }
            return entries
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
    }
}

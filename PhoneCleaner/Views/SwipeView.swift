import Photos
import SwiftUI

/// Photos the person chose to keep while swiping, so they don't come up again.
final class KeptPhotos {
    static let shared = KeptPhotos()

    private let url: URL
    private(set) var ids: Set<String>

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        url = support.appendingPathComponent("kept.json")
        ids = (try? JSONDecoder().decode(Set<String>.self, from: Data(contentsOf: url))) ?? []
    }

    func insert(_ id: String) { ids.insert(id); save() }
    func remove(_ id: String) { ids.remove(id); save() }
    func reset() { ids.removeAll(); save() }

    private func save() {
        try? JSONEncoder().encode(ids).write(to: url, options: .atomic)
    }
}

struct SwipeView: View {
    enum Order: String, CaseIterable, Identifiable {
        case screenshots = "Screenshots", newest = "Newest", oldest = "Oldest", random = "Random"
        var id: Self { self }
    }

    @Environment(Cleaner.self) private var cleaner
    @AppStorage("swipeOrder") private var order = Order.screenshots
    @State private var queue: [PHAsset] = []
    @State private var marked: [MediaItem] = []
    @State private var history: [(asset: PHAsset, deleted: Bool)] = []
    @State private var drag: CGSize = .zero
    @State private var loading = true
    @State private var showReview = false
    @State private var topBytes: Int64?
    @State private var flinging = false

    private let threshold: CGFloat = 110

    var body: some View {
        VStack(spacing: 16) {
            Picker("Order", selection: $order) {
                ForEach(Order.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            ZStack {
                if loading {
                    ProgressView()
                } else if queue.isEmpty {
                    ContentUnavailableView("You're all caught up", systemImage: "checkmark.circle",
                                           description: Text(marked.isEmpty ? "You've gone through every photo in this list."
                                                             : "Review the photos you marked to delete them."))
                } else {
                    if queue.count > 1 {
                        card(for: queue[1])
                            .scaleEffect(0.94)
                            .offset(y: 14)
                            .allowsHitTesting(false)
                    }
                    card(for: queue[0])
                        .overlay { stamps }
                        .offset(drag)
                        .rotationEffect(.degrees(Double(drag.width / 22)))
                        .gesture(
                            DragGesture()
                                .onChanged { drag = $0.translation }
                                .onEnded { value in
                                    if value.translation.width < -threshold { decide(delete: true) }
                                    else if value.translation.width > threshold { decide(delete: false) }
                                    else { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { drag = .zero } }
                                }
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(queue[0].mediaType == .video ? "Video" : "Photo")
                        .accessibilityAction(named: "Delete") { decide(delete: true) }
                        .accessibilityAction(named: "Keep") { decide(delete: false) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let asset = queue.first, !loading {
                Text([asset.creationDate?.formatted(date: .long, time: .omitted), topBytes?.formattedBytes].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .task(id: asset.localIdentifier) { topBytes = AssetSize.bytes(of: asset) }
            }

            controls
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Swipe Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Review (\(marked.count))") { showReview = true }
                .disabled(marked.isEmpty)
        }
        .sheet(isPresented: $showReview, onDismiss: {
            // Deleted photos can't come back with Undo.
            let stillMarked = Set(marked.map(\.id))
            history.removeAll { $0.deleted && !stillMarked.contains($0.asset.localIdentifier) }
        }) {
            SwipeReviewView(marked: $marked)
        }
        .task(id: order) { await load() }
    }

    private func card(for asset: PHAsset) -> some View {
        AssetImage(asset: asset, side: 700, fit: asset.mediaSubtypes.contains(.photoScreenshot))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if asset.mediaType == .video {
                    Label(Duration.seconds(asset.duration).formatted(.time(pattern: .minuteSecond)), systemImage: "video.fill")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(14)
                }
            }
            .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }

    private var stamps: some View {
        ZStack {
            stamp("DELETE", color: Theme.delete)
                .opacity(Double(max(-drag.width, 0) / threshold))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            stamp("KEEP", color: Theme.keep)
                .opacity(Double(max(drag.width, 0) / threshold))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(24)
    }

    private func stamp(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 34, weight: .heavy, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color, lineWidth: 4))
            .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
            .rotationEffect(.degrees(text == "KEEP" ? -14 : 14))
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 28) {
                roundButton("trash.fill", color: Theme.delete, size: 64, label: "Delete") { decide(delete: true) }
                    .disabled(queue.isEmpty)
                roundButton("arrow.uturn.backward", color: .gray, size: 48, label: "Undo") { undo() }
                    .disabled(history.isEmpty)
                roundButton("heart.fill", color: Theme.keep, size: 64, label: "Keep") { decide(delete: false) }
                    .disabled(queue.isEmpty)
            }
            Text(marked.isEmpty ? "Swipe left to delete, right to keep"
                 : "\(marked.count) marked to delete · \(marked.totalBytes.formattedBytes)")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private func roundButton(_ symbol: String, color: Color, size: CGFloat, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background(Color(.secondarySystemGroupedBackground), in: Circle())
                .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
        }
        .accessibilityLabel(label)
    }

    private func decide(delete: Bool) {
        guard let asset = queue.first, !flinging else { return }
        flinging = true
        withAnimation(.easeIn(duration: 0.2)) {
            drag = CGSize(width: delete ? -600 : 600, height: drag.height)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(200))
            queue.removeFirst()
            drag = .zero
            flinging = false
            history.append((asset, delete))
            if delete {
                marked.append(MediaItem(asset: asset, bytes: AssetSize.bytes(of: asset)))
            } else {
                KeptPhotos.shared.insert(asset.localIdentifier)
            }
        }
    }

    private func undo() {
        guard !flinging, let last = history.popLast() else { return }
        if last.deleted {
            marked.removeAll { $0.id == last.asset.localIdentifier }
        } else {
            KeptPhotos.shared.remove(last.asset.localIdentifier)
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            queue.insert(last.asset, at: 0)
        }
    }

    private func load() async {
        loading = true
        let order = order
        let skip = KeptPhotos.shared.ids.union(marked.map(\.id))
        queue = await Task.detached(priority: .userInitiated) {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: order == .oldest)]
            options.predicate = order == .screenshots
                ? NSPredicate(format: "(mediaSubtypes & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
                : NSPredicate(format: "mediaType == %d OR mediaType == %d", PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
            var assets: [PHAsset] = []
            PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, stop in
                guard !skip.contains(asset.localIdentifier) else { return }
                assets.append(asset)
                if order != .random && assets.count >= 500 { stop.pointee = true }
            }
            return order == .random ? Array(assets.shuffled().prefix(500)) : assets
        }.value
        history.removeAll()
        loading = false
        #if DEBUG
        // `-swipeDemo YES` marks the first few photos and leaves the next card mid-swipe, for App Store screenshots.
        if UserDefaults.standard.bool(forKey: "swipeDemo"), marked.isEmpty {
            for asset in queue.prefix(3) { marked.append(MediaItem(asset: asset, bytes: AssetSize.bytes(of: asset))) }
            queue.removeFirst(min(3, queue.count))
            drag = CGSize(width: -78, height: 8)
        }
        #endif
    }
}

/// Everything marked while swiping. Tap a photo to unmark it.
struct SwipeReviewView: View {
    @Binding var marked: [MediaItem]

    @Environment(\.dismiss) private var dismiss
    @State private var unmarked: Set<String> = []
    @State private var flow = CleanFlow()

    private var toDelete: [MediaItem] { marked.filter { !unmarked.contains($0.id) } }
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 6)]

    var body: some View {
        NavigationStack {
            Group {
                if marked.isEmpty {
                    ContentUnavailableView("Nothing to delete", systemImage: "checkmark.circle",
                                           description: Text("Photos you swipe left on show up here."))
                } else {
                    ScrollView {
                        Text("Tap a photo to keep it instead.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(marked) { item in
                                SelectableThumbnail(item: item, selected: !unmarked.contains(item.id))
                                    .onTapGesture {
                                        if unmarked.contains(item.id) { unmarked.remove(item.id) } else { unmarked.insert(item.id) }
                                    }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .safeAreaInset(edge: .bottom) {
                        DeleteBar(items: toDelete, flow: flow) {
                            let deleted = Set(toDelete.map(\.id))
                            marked.removeAll { deleted.contains($0.id) || unmarked.contains($0.id) }
                            unmarked.removeAll()
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .cleanFlow(flow)
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

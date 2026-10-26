import SwiftUI

/// Live Photos, largest saving first. Converting keeps each photo as a still and drops its video part.
struct LivePhotosView: View {
    @Environment(Cleaner.self) private var cleaner
    @State private var selection: Set<String> = []
    @State private var flow = CleanFlow()

    private var items: [MediaItem] { cleaner.livePhotos.sorted { $0.bytes > $1.bytes } }
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 6)]

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView("No Live Photos", systemImage: "livephoto",
                                       description: Text("Live Photos you take with the Camera app will show up here."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Keep the photo, drop the motion", systemImage: "livephoto.slash")
                                .font(.headline)
                            Text("Each Live Photo stores a short video next to the picture. Converting keeps the picture (with any edits), its date, location, favorite and albums, and removes only the video. The original goes to Recently Deleted for 30 days.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .card()
                        Text("\(items.count) Live Photos · \(items.totalBytes.formattedBytes) in motion")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(items) { item in
                                SelectableThumbnail(item: item, selected: selection.contains(item.id), badge: "LIVE")
                                    .onTapGesture {
                                        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
                                    }
                                    .contextMenu {
                                        Button(selection.contains(item.id) ? "Deselect" : "Select",
                                               systemImage: selection.contains(item.id) ? "circle" : "checkmark.circle") {
                                            if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
                                        }
                                    } preview: {
                                        AssetPreview(asset: item.asset)
                                    }
                            }
                        }
                    }
                    .padding()
                }
                .safeAreaInset(edge: .bottom) {
                    DeleteBar(items: items.filter { selection.contains($0.id) }, flow: flow, action: .convertToStills) {
                        selection.removeAll()
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .cleanFlow(flow)
        .navigationTitle("Live Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !items.isEmpty {
                Button(selection.count == items.count ? "Deselect All" : "Select All") {
                    selection = selection.count == items.count ? [] : Set(items.map(\.id))
                }
            }
        }
    }
}

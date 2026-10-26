import SwiftUI

/// Duplicates or similar photos, one card per set. Everything except the suggested best photo starts selected.
struct GroupsView: View {
    let kind: GroupKind

    @Environment(Cleaner.self) private var cleaner
    @State private var selection: Set<String> = []
    @State private var preselected = false
    @State private var flow = CleanFlow()

    private var groups: [MediaGroup] { kind == .duplicates ? cleaner.duplicates : cleaner.similar }
    private var selectedItems: [MediaItem] { groups.flatMap(\.items).filter { selection.contains($0.id) } }
    private var allExtraIDs: Set<String> { Set(groups.flatMap(\.extras).map(\.id)) }

    var body: some View {
        Group {
            if groups.isEmpty {
                ContentUnavailableView(kind == .duplicates ? "No duplicates" : "No similar photos",
                                       systemImage: "checkmark.seal",
                                       description: Text(kind == .duplicates
                                                         ? "You don't have any copies of the same photo."
                                                         : "No sets of near-identical shots were found."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        Text(kind == .duplicates
                             ? "The photo marked Best is kept. Tap any photo to change what gets deleted. Touch and hold to preview."
                             : "Similar shots taken close together. We suggest keeping the photo marked Best.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(groups) { group in
                            GroupCard(group: group, selection: $selection)
                        }
                    }
                    .padding()
                }
                .safeAreaInset(edge: .bottom) {
                    DeleteBar(items: selectedItems, flow: flow) { selection.removeAll() }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .cleanFlow(flow)
        .navigationTitle(kind == .duplicates ? "Duplicates" : "Similar Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !groups.isEmpty {
                Button(selection.isEmpty ? "Select All" : "Deselect All") {
                    selection = selection.isEmpty ? allExtraIDs : []
                }
            }
        }
        .task(id: cleaner.groupsReady) {
            // Preselect everything but the best photo once results are in.
            guard !preselected, !groups.isEmpty else { return }
            preselected = true
            selection = allExtraIDs
        }
    }
}

private struct GroupCard: View {
    let group: MediaGroup
    @Binding var selection: Set<String>

    private let columns = [GridItem(.adaptive(minimum: 78), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(group.items.count) photos")
                        .font(.headline)
                    if let date = group.date {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                let extras = Set(group.extras.map(\.id))
                Button(extras.isSubset(of: selection) ? "Keep All" : "Select Extras") {
                    if extras.isSubset(of: selection) {
                        selection.subtract(group.items.map(\.id))
                    } else {
                        selection.formUnion(extras)
                        selection.remove(group.best.id)
                    }
                }
                .font(.subheadline.weight(.semibold))
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(group.items) { item in
                    SelectableThumbnail(item: item, selected: selection.contains(item.id), badge: item == group.best ? "Best" : nil)
                        .onTapGesture { toggle(item) }
                        .contextMenu {
                            Button(selection.contains(item.id) ? "Keep" : "Delete",
                                   systemImage: selection.contains(item.id) ? "heart" : "trash") { toggle(item) }
                        } preview: {
                            AssetPreview(asset: item.asset)
                        }
                }
            }
        }
        .card()
    }

    private func toggle(_ item: MediaItem) {
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }
}

/// Screenshots (newest first) or large videos (largest first).
struct MediaGridView: View {
    let kind: MediaKind

    @Environment(Cleaner.self) private var cleaner
    @State private var selection: Set<String> = []
    @State private var flow = CleanFlow()

    private var items: [MediaItem] { kind == .screenshots ? cleaner.screenshots : cleaner.largeVideos }
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 6)]

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(kind == .screenshots ? "No screenshots" : "No large videos",
                                       systemImage: "checkmark.seal",
                                       description: Text(kind == .screenshots
                                                         ? "There are no screenshots in your library."
                                                         : "No videos larger than \(Cleaner.largeVideoBytes.formattedBytes) were found."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(items.count) \(kind == .screenshots ? "screenshots" : "videos") · \(items.totalBytes.formattedBytes)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(items) { item in
                                SelectableThumbnail(item: item, selected: selection.contains(item.id))
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
                    DeleteBar(items: items.filter { selection.contains($0.id) }, flow: flow) { selection.removeAll() }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .cleanFlow(flow)
        .navigationTitle(kind == .screenshots ? "Screenshots" : "Large Videos")
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

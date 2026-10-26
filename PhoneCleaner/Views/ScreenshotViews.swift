import Photos
import SwiftUI

/// Which screenshots a list shows.
enum ShotFilter: Hashable {
    case kind(ShotKind)
    case expired
    case all

    var title: String {
        switch self {
        case .kind(let kind): kind.title
        case .expired: "Ready to Clear"
        case .all: "All Screenshots"
        }
    }
}

/// A grid of screenshots. Tap one to read it; use Select to delete several.
struct ShotListView: View {
    let filter: ShotFilter

    @Environment(Cleaner.self) private var cleaner
    @State private var selecting = false
    @State private var selection: Set<String> = []
    @State private var flow = CleanFlow()
    @State private var preselected = false

    private var items: [MediaItem] {
        switch filter {
        case .kind(let kind): cleaner.shots(kind)
        case .expired: cleaner.expiredShots
        case .all: cleaner.screenshots
        }
    }
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(filter == .expired ? "Nothing out of date" : "No screenshots here",
                                       systemImage: "checkmark.seal",
                                       description: Text(filter == .expired
                                                         ? "Old one-time codes and tickets for past dates will show up here."
                                                         : "Screenshots of this kind will show up here."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if filter == .expired {
                            Text("One-time codes older than two days, and tickets and passes whose dates have all passed. Tap a screenshot to check it, or keep it to stop it showing here.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(items.count) \(items.count == 1 ? "screenshot" : "screenshots") · \(items.totalBytes.formattedBytes)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(items) { item in
                                cell(item)
                            }
                        }
                    }
                    .padding()
                }
                .safeAreaInset(edge: .bottom) {
                    if selecting {
                        DeleteBar(items: items.filter { selection.contains($0.id) }, flow: flow) {
                            selection.removeAll()
                        }
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .cleanFlow(flow)
        .navigationTitle(filter.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !items.isEmpty {
                if selecting {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(selection.count == items.count ? "Deselect All" : "Select All") {
                            selection = selection.count == items.count ? [] : Set(items.map(\.id))
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selecting ? "Done" : "Select") {
                        selecting.toggle()
                        if !selecting { selection.removeAll() }
                    }
                }
            }
        }
        .task(id: cleaner.textReady) {
            // Out-of-date screenshots open ready to delete; everything else opens for reading.
            guard filter == .expired, !preselected, !items.isEmpty else { return }
            preselected = true
            selecting = true
            selection = Set(items.map(\.id))
        }
    }

    @ViewBuilder
    private func cell(_ item: MediaItem) -> some View {
        if selecting {
            ShotThumbnail(item: item, selected: selection.contains(item.id))
                .onTapGesture {
                    if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
                }
        } else {
            NavigationLink(value: Destination.shot(item.id)) {
                ShotThumbnail(item: item, selected: nil)
            }
            .buttonStyle(.plain)
        }
    }
}

/// A portrait screenshot thumbnail with its date; shows a check mark while selecting.
struct ShotThumbnail: View {
    let item: MediaItem
    /// nil when not selecting.
    let selected: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            AssetImage(asset: item.asset, side: 220)
                .aspectRatio(0.56, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected == true ? Color.accentColor : Color(.separator), lineWidth: selected == true ? 3 : 0.5)
                }
                .overlay(alignment: .topTrailing) {
                    if let selected {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, selected ? Color.accentColor : .black.opacity(0.25))
                            .shadow(radius: 2)
                            .padding(6)
                    }
                }
            Text(item.asset.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? "")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Screenshot from \(item.asset.creationDate?.formatted(date: .long, time: .omitted) ?? "unknown date")")
        .accessibilityValue(selected == true ? "Selected" : "")
    }
}

/// One screenshot with the text Shotfile read from it.
struct ShotDetailView: View {
    let id: String

    @Environment(Cleaner.self) private var cleaner
    @Environment(\.dismiss) private var dismiss
    @State private var flow = CleanFlow()
    @State private var copied = false

    private var item: MediaItem? { cleaner.screenshots.first { $0.id == id } }

    var body: some View {
        Group {
            if let item {
                content(item)
            } else {
                ContentUnavailableView("Screenshot deleted", systemImage: "trash", description: Text("It's in Recently Deleted in the Photos app."))
            }
        }
        .background(Color(.systemGroupedBackground))
        .cleanFlow(flow)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ item: MediaItem) -> some View {
        let info = cleaner.shotInfo[item.id]
        let text = info?.text ?? ""
        let expired = info.map { ScreenshotAnalyzer.isExpired($0, created: item.asset.creationDate) } ?? false
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AssetImage(asset: item.asset, side: 900, fit: true)
                    .aspectRatio(CGFloat(max(item.asset.pixelWidth, 1)) / CGFloat(max(item.asset.pixelHeight, 1)), contentMode: .fit)
                    .frame(maxHeight: 520)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack(spacing: 8) {
                    if let kind = info?.kind {
                        Label(kind.title, systemImage: kind.symbol)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(kind.tint.opacity(0.15), in: Capsule())
                            .foregroundStyle(kind.tint)
                    }
                    if expired && !cleaner.keptIDs.contains(item.id) {
                        Label("Out of date", systemImage: "clock.badge.exclamationmark")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Theme.expired.opacity(0.15), in: Capsule())
                            .foregroundStyle(Theme.expired)
                    }
                    Spacer()
                    Text([item.asset.creationDate?.formatted(date: .abbreviated, time: .shortened), item.bytes.formattedBytes]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Text in this screenshot").font(.headline)
                        Spacer()
                        if !text.isEmpty {
                            Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc") {
                                UIPasteboard.general.string = text
                                copied = true
                            }
                            .font(.subheadline.weight(.semibold))
                            ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }
                                .accessibilityLabel("Share text")
                        }
                    }
                    Text(text.isEmpty ? "No text found." : text)
                        .font(.callout)
                        .foregroundStyle(text.isEmpty ? .secondary : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .card()

                if expired && !cleaner.keptIDs.contains(item.id) {
                    Button {
                        cleaner.keep(item)
                    } label: {
                        Label("Keep It (Stop Suggesting)", systemImage: "heart")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            DeleteBar(items: [item], flow: flow) { dismiss() }
        }
    }
}

/// Screenshots matching a search, with the line that matched.
struct ShotSearchResults: View {
    let query: String

    @Environment(Cleaner.self) private var cleaner

    var body: some View {
        let results = cleaner.search(query)
        Group {
            if !cleaner.textReady {
                ContentUnavailableView {
                    Label("Still reading your screenshots", systemImage: "text.viewfinder")
                } description: {
                    Text("Results will include every screenshot once Shotfile has read them.")
                }
            } else if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(results) { item in
                    NavigationLink(value: Destination.shot(item.id)) {
                        HStack(spacing: 12) {
                            AssetImage(asset: item.asset, side: 120)
                                .frame(width: 54, height: 96)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(snippet(cleaner.text(of: item) ?? ""))
                                    .font(.subheadline)
                                    .lineLimit(3)
                                Text(item.asset.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    /// The line containing the first search word, with every search word in bold.
    private func snippet(_ text: String) -> AttributedString {
        let terms = query.split(separator: " ").map(String.init)
        let line = text.split(separator: "\n").first { line in
            terms.contains { line.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }.map(String.init) ?? text
        var attributed = AttributedString(line)
        for term in terms {
            var searchRange = attributed.startIndex..<attributed.endIndex
            while let found = attributed[searchRange].range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
                attributed[found].font = .subheadline.bold()
                attributed[found].foregroundColor = .accentColor
                searchRange = found.upperBound..<attributed.endIndex
            }
        }
        return attributed
    }
}

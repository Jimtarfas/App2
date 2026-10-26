import SwiftUI

enum Destination: Hashable {
    case shots(ShotFilter)
    case shot(String)
    case groups(GroupKind)
    case media(MediaKind)
    case livePhotos
    case swipe
    case settings
}

struct HomeView: View {
    @Environment(Cleaner.self) private var cleaner
    @Environment(Store.self) private var store
    @AppStorage("introPaywallShown") private var introPaywallShown = false
    @State private var paywall: PaywallRequest?
    @State private var path: [Destination] = []
    @State private var query = ""

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    dashboard
                } else {
                    ShotSearchResults(query: query)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Shotfile")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search text in screenshots")
            .toolbar {
                if store.entitlementsLoaded && !store.isPremium {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            paywall = PaywallRequest()
                        } label: {
                            Label("Premium", systemImage: "crown.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.subheadline.weight(.semibold))
                        }
                        .tint(.orange)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: Destination.settings) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .shots(let filter): ShotListView(filter: filter)
                case .shot(let id): ShotDetailView(id: id)
                case .groups(let kind): GroupsView(kind: kind)
                case .media(let kind): MediaGridView(kind: kind)
                case .livePhotos: LivePhotosView()
                case .swipe: SwipeView()
                case .settings: SettingsView()
                }
            }
        }
        .fullScreenCover(item: $paywall) { request in
            PaywallView(reason: request.reason)
        }
        .onAppear(perform: openDebugRoute)
        .task(id: store.entitlementsLoaded) {
            // Offer Premium once, after the first photo-access prompt. It closes with one tap.
            guard store.entitlementsLoaded, !store.isPremium, !introPaywallShown else { return }
            introPaywallShown = true
            try? await Task.sleep(for: .milliseconds(600))
            paywall = PaywallRequest()
        }
    }

    private var dashboard: some View {
        ScrollView {
            VStack(spacing: 16) {
                ScreenshotSummaryCard()
                if cleaner.isLimited { LimitedAccessCard() }
                if cleaner.textReady && !cleaner.expiredShots.isEmpty { expiredCard }
                categoryGrid
                swipeCard
                libraryTools
                StorageCard()
                Label("Text is read on your iPhone. Nothing is uploaded.", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .refreshable { cleaner.scan() }
    }

    /// Debug builds only: `-route expired` (or a category, duplicates, similar, live, videos, swipe, settings, paywall, search:<text>,
    /// open:<word>, shot:<category>) opens that screen at launch.
    private func openDebugRoute() {
        #if DEBUG
        guard let route = UserDefaults.standard.string(forKey: "route") else { return }
        if route.hasPrefix("search:") { query = String(route.dropFirst(7)); return }
        if let kind = ShotKind(rawValue: route) { path = [.shots(.kind(kind))]; return }
        switch route {
        case "expired": path = [.shots(.expired)]
        case "duplicates": path = [.groups(.duplicates)]
        case "similar": path = [.groups(.similar)]
        case "live": path = [.livePhotos]
        case "videos": path = [.media(.videos)]
        case "swipe": path = [.swipe]
        case "settings": path = [.settings]
        case "paywall": paywall = PaywallRequest()
        default:
            if route.hasPrefix("open:") {
                // Opens the first screenshot containing a word once the text is read.
                Task {
                    while !cleaner.textReady { try? await Task.sleep(for: .milliseconds(300)) }
                    if let first = cleaner.search(String(route.dropFirst(5))).first { path = [.shot(first.id)] }
                }
            } else if route.hasPrefix("shot:"), let kind = ShotKind(rawValue: String(route.dropFirst(5))) {
                // Opens the first screenshot of a kind once the text is read.
                Task {
                    while !cleaner.textReady { try? await Task.sleep(for: .milliseconds(300)) }
                    if let first = cleaner.shots(kind).first { path = [.shot(first.id)] }
                }
            }
        }
        #endif
    }

    private var expiredCard: some View {
        let items = cleaner.expiredShots
        return NavigationLink(value: Destination.shots(.expired)) {
            HStack(spacing: 14) {
                Image(systemName: "clock.badge.exclamationmark.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Theme.expired.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(items.count) out-of-date \(items.count == 1 ? "screenshot" : "screenshots")")
                        .font(.headline)
                    Text("Old codes and past tickets · \(items.totalBytes.formattedBytes)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    private var categoryGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Screenshots by kind")
                .font(.title3.weight(.bold))
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(ShotKind.allCases) { kind in
                    let count = cleaner.shots(kind).count
                    NavigationLink(value: Destination.shots(.kind(kind))) {
                        VStack(alignment: .leading, spacing: 10) {
                            Image(systemName: kind.symbol)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(kind.tint.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(kind.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Text(cleaner.textReady ? "\(count)" : "–")
                                    .font(.rounded(.title3))
                                    .foregroundStyle(count == 0 ? .secondary : .primary)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!cleaner.textReady)
                }
            }
        }
        .padding(.top, 4)
    }

    private var swipeCard: some View {
        NavigationLink(value: Destination.swipe) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Swipe Review")
                        .font(.rounded(.title2))
                    Text("Go through screenshots one at a time: left to delete, right to keep.")
                        .font(.subheadline)
                        .opacity(0.9)
                }
                Spacer()
                Image(systemName: "hand.draw.fill")
                    .font(.system(size: 40))
            }
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var libraryTools: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Photo library")
                .font(.title3.weight(.bold))
            toolRow(.livePhotos, symbol: "livephoto", tint: .teal, title: "Live Photos to Stills",
                    detail: cleaner.livePhotos.isEmpty ? "None found" : "\(cleaner.livePhotos.count) · save \(cleaner.livePhotos.totalBytes.formattedBytes)",
                    ready: cleaner.listsReady)
            toolRow(.groups(.duplicates), symbol: "square.on.square.fill", tint: .blue, title: "Duplicate Photos",
                    detail: groupDetail(cleaner.duplicates, noun: "extra copy", plural: "extra copies"), ready: cleaner.groupsReady)
            toolRow(.groups(.similar), symbol: "photo.stack.fill", tint: .purple, title: "Similar Shots",
                    detail: groupDetail(cleaner.similar, noun: "similar shot", plural: "similar shots"), ready: cleaner.groupsReady)
            toolRow(.media(.videos), symbol: "film.fill", tint: .pink, title: "Large Videos",
                    detail: cleaner.largeVideos.isEmpty ? "None found" : "\(cleaner.largeVideos.count) · \(cleaner.largeVideos.totalBytes.formattedBytes)",
                    ready: cleaner.listsReady)
        }
        .padding(.top, 4)
    }

    private func toolRow(_ destination: Destination, symbol: String, tint: Color, title: String, detail: String, ready: Bool) -> some View {
        NavigationLink(value: destination) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(ready ? detail : "Checking…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if ready {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                } else {
                    ProgressView()
                }
            }
            .card()
        }
        .buttonStyle(.plain)
        .disabled(!ready)
    }

    private func groupDetail(_ groups: [MediaGroup], noun: String, plural: String) -> String {
        let extras = groups.reduce(0) { $0 + $1.extras.count }
        guard extras > 0 else { return "None found" }
        let bytes = groups.reduce(Int64(0)) { $0 + $1.reclaimableBytes }
        return "\(extras) \(extras == 1 ? noun : plural) · \(bytes.formattedBytes)"
    }
}

/// How many screenshots there are, and progress while their text is being read.
struct ScreenshotSummaryCard: View {
    @Environment(Cleaner.self) private var cleaner

    var body: some View {
        NavigationLink(value: Destination.shots(.all)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(cleaner.screenshots.count.formatted()) screenshots")
                            .font(.rounded(.title2))
                        Text("\(cleaner.screenshots.totalBytes.formattedBytes) on this iPhone")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                switch cleaner.textState {
                case .analyzing(let done, let total) where total > 0:
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: Double(done), total: Double(total))
                        Text("Reading text… \(done.formatted()) of \(total.formatted())")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                case .listing, .idle:
                    Label("Looking through your library…", systemImage: "magnifyingglass")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                default:
                    Label("Search any word you remember from a screenshot.", systemImage: "text.viewfinder")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .card()
        }
        .buttonStyle(.plain)
    }
}

struct StorageCard: View {
    @Environment(Cleaner.self) private var cleaner

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("iPhone Storage").font(.headline)
                Spacer()
                Text("\(cleaner.storage.available.formattedBytes) available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: cleaner.storage.usedFraction)
                .tint(cleaner.storage.usedFraction > 0.9 ? .red : .accentColor)
                .scaleEffect(x: 1, y: 2, anchor: .center)
                .padding(.vertical, 4)
            HStack {
                Text("\(cleaner.storage.used.formattedBytes) of \(cleaner.storage.total.formattedBytes) used")
                Spacer()
                if cleaner.freedBytes > 0 {
                    Label("\(cleaner.freedBytes.formattedBytes) freed", systemImage: "sparkles")
                        .foregroundStyle(Theme.keep)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .card()
    }
}

struct LimitedAccessCard: View {
    @Environment(Cleaner.self) private var cleaner

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Limited photo access", systemImage: "exclamationmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("Shotfile can only read the screenshots and photos you've shared with it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Choose More Photos") { cleaner.presentLimitedPicker() }
                .font(.subheadline.weight(.semibold))
        }
        .card()
    }
}

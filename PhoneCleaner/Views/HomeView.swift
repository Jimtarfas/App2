import SwiftUI

enum Destination: Hashable {
    case groups(GroupKind)
    case media(MediaKind)
    case swipe
    case settings
}

struct HomeView: View {
    @Environment(Cleaner.self) private var cleaner
    @Environment(Store.self) private var store
    @AppStorage("introPaywallShown") private var introPaywallShown = false
    @State private var paywall: PaywallRequest?
    @State private var path: [Destination] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 16) {
                    StorageCard()
                    if cleaner.isLimited { LimitedAccessCard() }
                    if cleaner.freedBytes > 0 { freedCard }
                    swipeCard
                    VStack(spacing: 10) {
                        categoryRow(.groups(.duplicates), symbol: "square.on.square.fill", tint: .blue, title: "Duplicates",
                                    detail: groupDetail(cleaner.duplicates, noun: "extra copy", plural: "extra copies"), ready: cleaner.groupsReady)
                        categoryRow(.groups(.similar), symbol: "photo.stack.fill", tint: .purple, title: "Similar Photos",
                                    detail: groupDetail(cleaner.similar, noun: "similar shot", plural: "similar shots"), ready: cleaner.groupsReady)
                        categoryRow(.media(.screenshots), symbol: "camera.viewfinder", tint: .orange, title: "Screenshots",
                                    detail: listDetail(cleaner.screenshots), ready: cleaner.listsReady)
                        categoryRow(.media(.videos), symbol: "film.fill", tint: .pink, title: "Large Videos",
                                    detail: listDetail(cleaner.largeVideos), ready: cleaner.listsReady)
                    }
                    Label("Scans run on your iPhone. Nothing is uploaded.", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Phone Cleaner")
            .refreshable { cleaner.scan() }
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
                case .groups(let kind): GroupsView(kind: kind)
                case .media(let kind): MediaGridView(kind: kind)
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

    /// Debug builds only: `-route swipe` (or duplicates, similar, screenshots, videos, settings, paywall) opens that screen at launch.
    private func openDebugRoute() {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "route") {
        case "duplicates": path = [.groups(.duplicates)]
        case "similar": path = [.groups(.similar)]
        case "screenshots": path = [.media(.screenshots)]
        case "videos": path = [.media(.videos)]
        case "swipe": path = [.swipe]
        case "settings": path = [.settings]
        case "paywall": paywall = PaywallRequest()
        default: break
        }
        #endif
    }

    private var freedCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Theme.keep.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(cleaner.freedBytes.formattedBytes) cleared")
                    .font(.rounded(.title3))
                Text("\(cleaner.freedItems) photos and videos removed with Phone Cleaner")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var swipeCard: some View {
        NavigationLink(value: Destination.swipe) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Swipe to Clean")
                        .font(.rounded(.title2))
                    Text("Keep or delete your photos one at a time.")
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

    private func categoryRow(_ destination: Destination, symbol: String, tint: Color, title: String, detail: String, ready: Bool) -> some View {
        NavigationLink(value: destination) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(ready ? detail : "Scanning…")
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

    private func listDetail(_ items: [MediaItem]) -> String {
        items.isEmpty ? "None found" : "\(items.count) · \(items.totalBytes.formattedBytes)"
    }
}

struct StorageCard: View {
    @Environment(Cleaner.self) private var cleaner

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("iPhone Storage").font(.headline)
                Spacer()
                Text("\(cleaner.storage.available.formattedBytes) available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: cleaner.storage.usedFraction)
                .tint(cleaner.storage.usedFraction > 0.9 ? .red : .accentColor)
                .scaleEffect(x: 1, y: 2.2, anchor: .center)
                .padding(.vertical, 4)
            Text("\(cleaner.storage.used.formattedBytes) of \(cleaner.storage.total.formattedBytes) used")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            HStack {
                stat("\(cleaner.photoCount.formatted())", "Photos")
                stat("\(cleaner.videoCount.formatted())", "Videos")
                stat("\(cleaner.screenshots.count.formatted())", "Screenshots")
            }

            if case .analyzing(let done, let total) = cleaner.scanState, total > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(done), total: Double(total))
                    Text("Looking for duplicates and similar shots… \(done.formatted()) of \(total.formatted())")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            } else if cleaner.scanState == .listing {
                Label("Reading your photo library…", systemImage: "magnifyingglass")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.rounded(.title3))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct LimitedAccessCard: View {
    @Environment(Cleaner.self) private var cleaner

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Limited photo access", systemImage: "exclamationmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("Phone Cleaner can only check the photos you've shared with it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Choose More Photos") { cleaner.presentLimitedPicker() }
                .font(.subheadline.weight(.semibold))
        }
        .card()
    }
}

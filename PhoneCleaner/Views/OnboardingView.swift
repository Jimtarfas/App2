import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void

    @State private var page = 0

    private let pages: [(symbol: String, title: String, text: String)] = [
        ("square.on.square", "Find duplicate & similar photos",
         "Phone Cleaner groups copies and near-identical shots so you can keep the best one and delete the rest."),
        ("hand.draw", "Swipe to keep or delete",
         "Go through your photos one at a time. Swipe left to delete, swipe right to keep."),
        ("internaldrive", "Free up photo storage",
         "Spot large videos and old screenshots, and see exactly how much space you've cleared."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    let page = pages[index]
                    VStack(spacing: 28) {
                        Spacer()
                        Image(systemName: page.symbol)
                            .font(.system(size: 64, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 150, height: 150)
                            .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 40, style: .continuous))
                            .shadow(color: .blue.opacity(0.25), radius: 20, y: 10)
                        VStack(spacing: 12) {
                            Text(page.title)
                                .font(.rounded(.title))
                                .multilineTextAlignment(.center)
                            Text(page.text)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 32)
                        Spacer()
                        Spacer()
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Text(page < pages.count - 1 ? "Next" : "Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .background(Color(.systemBackground))
    }
}

/// Explains photo access before iOS asks for it.
struct PermissionView: View {
    @Environment(Cleaner.self) private var cleaner

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 128, height: 128)
                .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            Text("Let Phone Cleaner see your photos")
                .font(.rounded(.title2))
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 16) {
                point("iphone", "The scan runs on your iPhone. Your photos are never uploaded.")
                point("hand.tap", "Nothing is deleted until you choose it and confirm.")
                point("arrow.uturn.backward", "Deleted items stay in Recently Deleted for 30 days.")
            }
            .card()
            Spacer()
            Button {
                Task { await cleaner.requestAccess() }
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
        }
        .padding(24)
        .background(Color(.systemGroupedBackground))
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            Text(text).font(.subheadline)
        }
    }
}

struct AccessDeniedView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ContentUnavailableView {
            Label("Photo access is off", systemImage: "photo.badge.exclamationmark")
        } description: {
            Text("Phone Cleaner needs access to your photo library to find duplicates, screenshots and large videos. You can turn it on in Settings.")
        } actions: {
            Button("Open Settings") { openURL(Links.settings) }
                .buttonStyle(.borderedProminent)
        }
    }
}

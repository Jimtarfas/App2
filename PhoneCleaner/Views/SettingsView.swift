import StoreKit
import SwiftUI

struct SettingsView: View {
    @Environment(Cleaner.self) private var cleaner
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var paywall: PaywallRequest?
    @State private var managing = false
    @State private var message: String?
    @State private var restoring = false
    @State private var confirmReset = false

    var body: some View {
        List {
            Section {
                if store.isPremium {
                    Label("Premium is active", systemImage: "crown.fill")
                        .foregroundStyle(.orange)
                    Button("Manage Subscription") { managing = true }
                } else {
                    Button {
                        paywall = PaywallRequest()
                    } label: {
                        Label("Go Premium", systemImage: "crown.fill")
                    }
                    LabeledContent("Free deletions left today", value: "\(cleaner.freeDeletesLeft) of \(Cleaner.freeDeletesPerDay)")
                }
                Button {
                    Task { await restore() }
                } label: {
                    HStack {
                        Text("Restore Purchases")
                        if restoring { Spacer(); ProgressView() }
                    }
                }
                .disabled(restoring)
            } header: {
                Text("Subscription")
            }

            Section("Photo Access") {
                LabeledContent("Access", value: cleaner.isLimited ? "Selected photos" : "All photos")
                if cleaner.isLimited {
                    Button("Choose More Photos") { cleaner.presentLimitedPicker() }
                }
                Button("Open iPhone Settings") { openURL(Links.settings) }
                Button("Show Photos I Kept Again") { confirmReset = true }
            }

            Section {
                LabeledContent("Total freed", value: cleaner.freedBytes.formattedBytes)
                LabeledContent("Items removed", value: cleaner.freedItems.formatted())
            } header: {
                Text("Your Cleanup")
            } footer: {
                Text("Deleted items stay in Recently Deleted in the Photos app for 30 days before the space is released.")
            }

            Section("About") {
                Button("Privacy Policy") { openURL(Links.privacy) }
                Button("Terms of Use") { openURL(Links.terms) }
                Button("Contact Support") { openURL(Links.support) }
                Button("Rate Phone Cleaner") { openURL(Links.review) }
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $paywall) { request in
            PaywallView(reason: request.reason)
        }
        .manageSubscriptionsSheet(isPresented: $managing)
        .confirmationDialog("Photos you kept while swiping will show up in Swipe to Clean again.", isPresented: $confirmReset,
                            titleVisibility: .visible) {
            Button("Show Them Again") { KeptPhotos.shared.reset() }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        }
    }

    private func restore() async {
        restoring = true
        defer { restoring = false }
        do {
            message = try await store.restore()
                ? "Your Premium subscription has been restored."
                : "No active Phone Cleaner subscription was found for this Apple Account."
        } catch {
            message = "Couldn't restore purchases. \(error.localizedDescription)"
        }
    }
}

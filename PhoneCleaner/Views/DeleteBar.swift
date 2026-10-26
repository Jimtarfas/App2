import Observation
import StoreKit
import SwiftUI

/// What a cleaning screen presents after the delete button is tapped. Owned by the screen, not the bar,
/// so the result still shows when the deletion empties the list and the bar goes away.
@Observable
final class CleanFlow {
    var paywall: PaywallRequest?
    var result: CleanResult?
    var error: String?
}

struct CleanResult: Identifiable {
    let id = UUID()
    let items: Int
    let bytes: Int64
}

private struct CleanFlowPresenter: ViewModifier {
    @Bindable var flow: CleanFlow

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $flow.paywall) { request in
                PaywallView(reason: request.reason)
            }
            .sheet(item: $flow.result) { result in
                CleanResultView(result: result)
            }
            .alert("Couldn't delete", isPresented: Binding(get: { flow.error != nil }, set: { if !$0 { flow.error = nil } }),
                   presenting: flow.error) { _ in
                Button("OK") {}
            } message: { message in
                Text(message)
            }
    }
}

extension View {
    func cleanFlow(_ flow: CleanFlow) -> some View { modifier(CleanFlowPresenter(flow: flow)) }
}

/// The bottom bar on every cleaning screen. Checks the free plan, then asks Photos to delete.
struct DeleteBar: View {
    let items: [MediaItem]
    let flow: CleanFlow
    var onDeleted: () -> Void = {}

    @Environment(Cleaner.self) private var cleaner
    @Environment(Store.self) private var store
    @State private var deleting = false

    var body: some View {
        VStack(spacing: 8) {
            Button {
                Task { await delete() }
            } label: {
                HStack {
                    if deleting { ProgressView().tint(.white) } else { Image(systemName: "trash") }
                    Text(items.isEmpty ? "Select items to delete" : "Delete \(items.count) · \(items.totalBytes.formattedBytes)")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .tint(Theme.delete)
            .disabled(items.isEmpty || deleting)

            if store.entitlementsLoaded && !store.isPremium {
                Text("Free plan: \(cleaner.freeDeletesLeft) of \(Cleaner.freeDeletesPerDay) deletions left today")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private func delete() async {
        let premium = store.isPremium
        if !premium && !cleaner.freePlanAllows(items.count) {
            flow.paywall = PaywallRequest(reason: cleaner.freeDeletesLeft == 0
                ? "You've used today's \(Cleaner.freeDeletesPerDay) free deletions. They reset tomorrow, or go Premium to delete without limits."
                : "The free plan has \(cleaner.freeDeletesLeft) deletions left today. Go Premium to delete all \(items.count) at once.")
            return
        }
        deleting = true
        defer { deleting = false }
        let batch = items
        do {
            if let bytes = try await cleaner.delete(batch, countsAgainstFreePlan: !premium) {
                onDeleted()
                flow.result = CleanResult(items: batch.count, bytes: bytes)
            }
        } catch {
            flow.error = error.localizedDescription
        }
    }
}

/// Shown after a successful deletion.
struct CleanResultView: View {
    let result: CleanResult

    @Environment(Cleaner.self) private var cleaner
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @AppStorage("askedForReview") private var askedForReview = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 84))
                .foregroundStyle(.white, Theme.keep)
                .scaleEffect(appeared ? 1 : 0.4)
                .opacity(appeared ? 1 : 0)
            Text(result.bytes.formattedBytes)
                .font(.system(size: 52, weight: .heavy, design: .rounded))
            Text("of photo and video storage freed")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("\(result.items) \(result.items == 1 ? "item" : "items") moved to Recently Deleted")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                Label("Total freed with Phone Cleaner: \(cleaner.freedBytes.formattedBytes)", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                Label("Photos keeps deleted items in Recently Deleted for 30 days. Empty it in the Photos app to get the space back right away.",
                      systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .card()
            .padding(.top, 8)

            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Done").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
        }
        .padding(24)
        .background(Color(.systemGroupedBackground))
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { appeared = true }
        }
        .onDisappear {
            if !askedForReview && result.bytes >= 50_000_000 {
                askedForReview = true
                requestReview()
            }
        }
    }
}

import Observation
import StoreKit
import SwiftUI

/// What a screen presents after its action button is tapped. Owned by the screen, not the bar,
/// so the result still shows when the action empties the list and the bar goes away.
@Observable
final class CleanFlow {
    var paywall: PaywallRequest?
    var result: CleanResult?
    var error: String?
}

struct CleanResult: Identifiable {
    enum Kind { case deleted, converted }
    let id = UUID()
    let kind: Kind
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
            .alert("Something went wrong", isPresented: Binding(get: { flow.error != nil }, set: { if !$0 { flow.error = nil } }),
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

/// The bottom bar on every list. Checks the free plan, then deletes (or converts Live Photos) through Photos.
struct DeleteBar: View {
    enum Action { case delete, convertToStills }

    let items: [MediaItem]
    let flow: CleanFlow
    var action: Action = .delete
    var onDone: () -> Void = {}

    @Environment(Cleaner.self) private var cleaner
    @Environment(Store.self) private var store
    @State private var working = false

    private var title: String {
        if items.isEmpty { return action == .delete ? "Select items to delete" : "Select Live Photos to convert" }
        return action == .delete
            ? "Delete \(items.count) · \(items.totalBytes.formattedBytes)"
            : "Convert \(items.count) · Save \(items.totalBytes.formattedBytes)"
    }

    var body: some View {
        VStack(spacing: 8) {
            Button {
                Task { await run() }
            } label: {
                HStack {
                    if working {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: action == .delete ? "trash" : "livephoto.slash")
                    }
                    Text(title)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .tint(action == .delete ? Theme.delete : .accentColor)
            .disabled(items.isEmpty || working)

            if store.entitlementsLoaded && !store.isPremium {
                Text("Free plan: \(cleaner.freeActionsLeft) of \(Cleaner.freeActionsPerDay) left today")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private func run() async {
        let premium = store.isPremium
        if !premium && !cleaner.freePlanAllows(items.count) {
            let left = cleaner.freeActionsLeft
            flow.paywall = PaywallRequest(reason: left == 0
                ? "You've used today's \(Cleaner.freeActionsPerDay) free deletions and conversions. They reset tomorrow, or go Premium for no daily limit."
                : "The free plan has \(left) left today. Go Premium to do all \(items.count) at once.")
            return
        }
        working = true
        defer { working = false }
        let batch = items
        do {
            switch action {
            case .delete:
                if let bytes = try await cleaner.delete(batch, countsAgainstFreePlan: !premium) {
                    onDone()
                    flow.result = CleanResult(kind: .deleted, items: batch.count, bytes: bytes)
                }
            case .convertToStills:
                if let bytes = try await cleaner.convertToStills(batch, countsAgainstFreePlan: !premium) {
                    onDone()
                    flow.result = CleanResult(kind: .converted, items: batch.count, bytes: bytes)
                }
            }
        } catch {
            flow.error = error.localizedDescription
        }
    }
}

/// Shown after a successful deletion or conversion.
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
            Text(result.kind == .deleted ? "of storage freed" : "saved by turning Live Photos into stills")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text(result.kind == .deleted
                 ? "\(result.items) \(result.items == 1 ? "item" : "items") moved to Recently Deleted"
                 : "\(result.items) \(result.items == 1 ? "photo" : "photos") kept as stills")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                Label("Total freed with Shotfile: \(cleaner.freedBytes.formattedBytes)", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                Label(result.kind == .deleted
                      ? "Photos keeps deleted items in Recently Deleted for 30 days. Empty it in the Photos app to get the space back right away."
                      : "The Live Photos went to Recently Deleted, so you can still get them back for 30 days. Empty it in the Photos app to get the space back right away.",
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

import StoreKit
import SwiftUI

struct PaywallRequest: Identifiable {
    let id = UUID()
    var reason: String?
}

struct PaywallView: View {
    var reason: String? = nil

    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var selectedID = Store.yearlyID
    @State private var working = false
    @State private var message: String?

    private var selected: Product? { store.products.first { $0.id == selectedID } }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    features
                    if store.products.isEmpty {
                        loadingPlans
                    } else {
                        plans
                        purchaseButton
                    }
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 44)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .accessibilityLabel("Close")
            .padding(.trailing, 16)
            .padding(.top, 8)
        }
        .background(Color(.systemGroupedBackground))
        .onChange(of: store.isPremium) { _, premium in
            if premium { dismiss() }
        }
        .task {
            if store.products.isEmpty { await store.loadProducts() }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            Text("Phone Cleaner Premium")
                .font(.rounded(.title))
                .multilineTextAlignment(.center)
            if let reason {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 14) {
            feature("infinity", "Unlimited deletions", "The free plan deletes up to \(Cleaner.freeDeletesPerDay) items a day.")
            feature("square.on.square", "Clear every duplicate at once", "Delete whole sets of duplicates and similar shots in one go.")
            feature("film.stack", "Large videos and screenshots", "Free up photo and video storage in bulk.")
            feature("lock.shield", "Private by design", "Your photos are analyzed on your iPhone and never uploaded.")
        }
        .card()
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var loadingPlans: some View {
        VStack(spacing: 12) {
            if store.loadFailed {
                Text("Couldn't load subscription options. Check your connection and try again.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again") { Task { await store.loadProducts() } }
                    .buttonStyle(.bordered)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }

    private var plans: some View {
        VStack(spacing: 12) {
            if let yearly = store.yearly { planCard(yearly) }
            if let weekly = store.weekly { planCard(weekly) }
        }
    }

    private func planCard(_ product: Product) -> some View {
        let isSelected = product.id == selectedID
        let trial = product.id == Store.yearlyID && store.yearlyTrialEligible ? product.freeTrialLength : nil
        return Button {
            selectedID = product.id
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(product.id == Store.yearlyID ? "Yearly" : "Weekly")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if let savings = savings(for: product) {
                            Text("SAVE \(savings)%")
                                .font(.caption2.weight(.heavy))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.accentColor, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    Text("\(product.displayPrice) / \(product.periodName)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                    if let trial {
                        Text("\(trial) free trial, then \(product.displayPrice) per \(product.periodName)")
                            .font(.footnote)
                            .foregroundStyle(.primary)
                    }
                    if product.id == Store.yearlyID, let perWeek = product.weeklyEquivalent {
                        Text("Works out to \(perWeek.formatted(product.priceFormatStyle)) per week")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color(.separator), lineWidth: isSelected ? 2.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Percentage saved by the yearly plan compared with paying weekly for a year.
    private func savings(for product: Product) -> Int? {
        guard product.id == Store.yearlyID, let weekly = store.weekly,
              let yearlyWeekly = product.weeklyEquivalent, let weeklyWeekly = weekly.weeklyEquivalent, weeklyWeekly > 0 else { return nil }
        let ratio = NSDecimalNumber(decimal: 1 - yearlyWeekly / weeklyWeekly).doubleValue
        let percent = Int((ratio * 100).rounded(.down))
        return percent >= 10 ? percent : nil
    }

    private var purchaseButton: some View {
        let trial = selectedID == Store.yearlyID && store.yearlyTrialEligible ? selected?.freeTrialLength : nil
        return VStack(spacing: 10) {
            Button {
                Task { await purchase() }
            } label: {
                Group {
                    if working {
                        ProgressView().tint(.white)
                    } else {
                        Text(trial != nil ? "Start Free Trial" : "Continue")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .disabled(selected == nil || working)

            if let product = selected {
                Text(trial != nil && product.freeTrialDuration != nil
                     ? "Free for \(product.freeTrialDuration!), then \(product.displayPrice) per \(product.periodName). Cancel anytime."
                     : "\(product.displayPrice) per \(product.periodName). Renews automatically. Cancel anytime.")
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 18) {
                Button("Restore Purchases") { Task { await restore() } }
                Button("Terms of Use") { openURL(Links.terms) }
                Button("Privacy Policy") { openURL(Links.privacy) }
            }
            .font(.footnote.weight(.semibold))
            .disabled(working)

            Text("Payment is charged to your Apple Account when you confirm the purchase, or when the free trial ends if you start one. The subscription renews automatically at the same price for the same period unless you turn off auto-renew at least 24 hours before the current period ends. You can manage or cancel it anytime in your Apple Account settings. If you cancel during a free trial, you won't be charged.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func purchase() async {
        guard let product = selected else { return }
        working = true
        defer { working = false }
        do {
            switch try await store.purchase(product) {
            case .purchased: dismiss()
            case .pending: message = "Your purchase is waiting for approval. Premium unlocks as soon as it's approved."
            case .cancelled: break
            }
        } catch {
            message = "The purchase didn't go through. \(error.localizedDescription)"
        }
    }

    private func restore() async {
        working = true
        defer { working = false }
        do {
            if try await store.restore() {
                dismiss()
            } else {
                message = "No active Phone Cleaner subscription was found for this Apple Account."
            }
        } catch {
            message = "Couldn't restore purchases. \(error.localizedDescription)"
        }
    }
}

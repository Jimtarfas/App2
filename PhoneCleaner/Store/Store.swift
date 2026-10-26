import Observation
import StoreKit

/// Shotfile Premium: one auto-renewable subscription group with a monthly and a yearly plan.
@MainActor
@Observable
final class Store {
    static let monthlyID = "com.cleanupphotos.app.shotfile.monthly"
    static let yearlyID = "com.cleanupphotos.app.shotfile.yearly"
    static let productIDs: Set<String> = [monthlyID, yearlyID]

    private(set) var products: [Product] = []
    private(set) var isPremium = false
    private(set) var entitlementsLoaded = false
    private(set) var loadFailed = false
    private(set) var yearlyTrialEligible = false

    private var updates: Task<Void, Never>?

    init() {
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update { await transaction.finish() }
                await self?.refreshEntitlements()
            }
        }
        Task {
            await refreshEntitlements()
            await loadProducts()
        }
    }

    var monthly: Product? { products.first { $0.id == Self.monthlyID } }
    var yearly: Product? { products.first { $0.id == Self.yearlyID } }

    func loadProducts() async {
        do {
            products = try await Product.products(for: Self.productIDs)
            loadFailed = products.isEmpty
        } catch {
            loadFailed = true
        }
        if let subscription = yearly?.subscription, subscription.introductoryOffer != nil {
            yearlyTrialEligible = await subscription.isEligibleForIntroOffer
        } else {
            yearlyTrialEligible = false
        }
    }

    enum Outcome { case purchased, cancelled, pending }

    func purchase(_ product: Product) async throws -> Outcome {
        switch try await product.purchase() {
        case .success(let verification):
            let transaction = try verification.payloadValue
            await transaction.finish()
            await refreshEntitlements()
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// Syncs with the App Store and returns whether a subscription is active.
    func restore() async throws -> Bool {
        try await AppStore.sync()
        await refreshEntitlements()
        return isPremium
    }

    func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               Self.productIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                active = true
            }
        }
        isPremium = active
        entitlementsLoaded = true
    }
}

extension Product.SubscriptionPeriod {
    /// StoreKit can report a one-week period as seven days; count it in weeks.
    var normalized: (value: Int, unit: Unit) {
        unit == .day && value % 7 == 0 ? (value / 7, .week) : (value, unit)
    }

    /// "week", "3 days"
    var name: String {
        let (value, unit) = normalized
        return value == 1 ? unit.word : "\(value) \(unit.word)s"
    }
}

extension Product.SubscriptionPeriod.Unit {
    var word: String {
        switch self {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        case .year: "year"
        @unknown default: "period"
        }
    }
}

extension Product {
    /// "week", "year"
    var periodName: String { subscription?.subscriptionPeriod.name ?? "" }

    /// "3-day" for a three-day free trial, nil when there's no free trial.
    var freeTrialLength: String? {
        guard let offer = subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        let (value, unit) = offer.period.normalized
        return "\(value)-\(unit.word)"
    }

    /// "3 days" for a three-day free trial.
    var freeTrialDuration: String? {
        guard let offer = subscription?.introductoryOffer, offer.paymentMode == .freeTrial else { return nil }
        return offer.period.name.first?.isNumber == true ? offer.period.name : "1 \(offer.period.name)"
    }

    /// The price spread over one month, for comparing plans.
    var monthlyEquivalent: Decimal? {
        guard let period = subscription?.subscriptionPeriod else { return nil }
        let (value, unit) = period.normalized
        let months: Decimal = switch unit {
        case .day: Decimal(value) * 12 / 365
        case .week: Decimal(value) * 12 / 52
        case .month: Decimal(value)
        case .year: Decimal(value) * 12
        @unknown default: 1
        }
        return price / months
    }
}

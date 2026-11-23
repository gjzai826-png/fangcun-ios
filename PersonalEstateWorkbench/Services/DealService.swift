import Foundation

enum DealService {
    static func fillSnapshots(_ deal: Deal, property: Property, contact: Contact?) {
        deal.communityNameSnapshot = property.community?.name ?? ""
        let pieces = [property.doorText, property.layoutText, property.areaText].filter { !$0.isEmpty }
        deal.propertyDescriptionSnapshot = pieces.joined(separator: " · ")
        deal.counterpartyNameSnapshot = contact?.displayName ?? property.owner?.displayName ?? ""
    }

    static func markRegistered(_ deal: Deal, property: Property) {
        let target: PropertyStatus = deal.kind == .sale ? .sold : .rented
        PropertyService.recordStatusChange(
            of: property,
            to: target,
            reason: "登记成交",
            relatedDealID: deal.id
        )
    }

    static func void(_ deal: Deal, reason: String) {
        deal.status = .voided
        deal.voidReason = BusinessRules.trimmed(reason)
        deal.updatedAt = Date()
        if let property = deal.property {
            PropertyService.recordStatusChange(
                of: property,
                to: .needsVerification,
                reason: "成交已作废，房源转为待核实，没有自动上架",
                relatedDealID: deal.id
            )
        }
    }

    static func endLease(_ deal: Deal) {
        deal.status = .ended
        deal.updatedAt = Date()
        if let property = deal.property {
            PropertyService.recordStatusChange(
                of: property,
                to: .needsVerification,
                reason: "已退租，房源待检查，没有自动上架",
                relatedDealID: deal.id
            )
        }
    }

    static func otherActiveLeaseRanges(property: Property, excluding dealID: UUID?) -> [(Date, Date)] {
        property.deals.compactMap { deal in
            guard deal.id != dealID, deal.kind == .rent, deal.status == .active,
                  let start = deal.leaseStartOn, let end = deal.leaseEndOn else { return nil }
            return (start, end)
        }
    }

    static func performance(deals: [Deal]) -> (saleCents: Int, rentCents: Int, receivedCents: Int) {
        let counted = deals.filter { $0.status.countsTowardPerformance }
        let sale = counted.filter { $0.kind == .sale }.reduce(0) { $0 + $1.actualPriceCents }
        let rent = counted.filter { $0.kind == .rent }.reduce(0) { $0 + $1.actualPriceCents }
        let received = counted.reduce(0) { $0 + $1.commissionReceivedCents }
        return (sale, rent, received)
    }

    /// 分佣基数 = 成交价 × 80%；费用按勾选比例从基数里扣；到手 = 扣除后 × 80%。
    static func estimatedReceivable(priceCents: Int, allocation: DealCommissionAllocation) -> Int {
        let base = Double(priceCents) * 0.80
        var rate = Double(allocation.followUpPercent)
        if allocation.photoFee { rate += 2 }
        if allocation.propertyFee { rate += 12 }
        if allocation.keyFee { rate += 5 }
        let fee = base * rate / 100
        return max(0, Int(((base - fee) * 0.80).rounded()))
    }

    static func makeComparable(from deal: Deal) -> MarketComparable? {
        guard let property = deal.property else { return nil }
        let comparable = MarketComparable(
            kind: deal.kind.listingKind,
            dealDate: deal.signedOn,
            priceCents: deal.actualPriceCents,
            area: property.area,
            bedrooms: property.bedrooms,
            decoration: property.decoration,
            floorDescription: property.floorText,
            sourceDescription: "个人成交摘录",
            notes: "由成交 \(deal.displayNumber) 另存，不计入行情以外的业绩。"
        )
        comparable.community = property.community
        return comparable
    }
}

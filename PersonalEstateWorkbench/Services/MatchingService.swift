import Foundation

struct MatchRow: Identifiable {
    var id: UUID
    var title: String
    var subtitle: String
    var bucket: MatchBucket
    var notes: [String]
    var propertyID: UUID?
    var needID: UUID?
}

enum MatchingService {
    static func properties(for need: ClientNeed, properties: [Property], viewings: [Viewing]) -> [MatchRow] {
        let rejected = rejectedPropertyIDs(needID: need.id, viewings: viewings)
        return properties.compactMap { property in
            evaluate(property: property, need: need, rejected: rejected.contains(property.id))
        }
        .sorted { lhs, rhs in
            if lhs.bucket != rhs.bucket {
                return bucketOrder(lhs.bucket) < bucketOrder(rhs.bucket)
            }
            return lhs.title < rhs.title
        }
    }

    static func needs(for property: Property, needs: [ClientNeed], viewings: [Viewing]) -> [MatchRow] {
        needs.compactMap { need in
            let rejected = rejectedPropertyIDs(needID: need.id, viewings: viewings).contains(property.id)
            guard var row = evaluate(property: property, need: need, rejected: rejected) else { return nil }
            row.id = need.id
            row.propertyID = property.id
            row.needID = need.id
            row.title = need.contact?.displayName ?? "未关联联系人"
            row.subtitle = "\(need.kind.title) · \(need.budgetText) · \(need.urgency.title)"
            return row
        }
        .sorted { bucketOrder($0.bucket) < bucketOrder($1.bucket) }
    }

    private static func bucketOrder(_ bucket: MatchBucket) -> Int {
        switch bucket {
        case .qualified: return 0
        case .needsVerification: return 1
        case .previouslyRejected: return 2
        case .excluded: return 3
        }
    }

    private static func rejectedPropertyIDs(needID: UUID, viewings: [Viewing]) -> Set<UUID> {
        Set(viewings.filter { $0.clientNeed?.id == needID }.flatMap { viewing in
            viewing.items.compactMap { item in
                item.interest == .dislike ? item.property?.id : nil
            }
        })
    }

    private static func evaluate(property: Property, need: ClientNeed, rejected: Bool) -> MatchRow? {
        if property.isArchived { return nil }
        var notes: [String] = []
        var hardFail = false

        if property.listingKind == need.kind.matchingListing {
            notes.append("租售类型一致：\(property.listingKind.title)")
        } else {
            hardFail = true
            notes.append("租售类型不一致：房源是\(property.listingKind.title)，需求是\(need.kind.title)")
        }

        if need.budgetMinCents > 0 || need.budgetMaxCents > 0 {
            if property.askingPriceCents <= 0 {
                notes.append("报价未填，没有按预算排除")
            } else if need.budgetMaxCents > 0 && property.askingPriceCents > need.budgetMaxCents {
                hardFail = true
                notes.append("价格高于预算上限")
            } else if need.budgetMinCents > 0 && property.askingPriceCents < need.budgetMinCents {
                hardFail = true
                notes.append("价格低于预算下限")
            } else {
                notes.append("价格在预算内")
            }
        }

        if !need.preferredDistricts.isEmpty {
            let district = property.community?.district ?? ""
            if district.isEmpty {
                notes.append("小区未填区域，没有按区域排除")
            } else if need.preferredDistricts.contains(district) {
                notes.append("区域符合：\(district)")
            } else {
                hardFail = true
                notes.append("区域不符合：\(district)")
            }
        }

        if !need.preferredCommunityIDs.isEmpty {
            if let id = property.community?.id, need.preferredCommunityIDs.contains(id) {
                notes.append("小区在偏好名单里")
            } else {
                hardFail = true
                notes.append("不在偏好小区里")
            }
        }

        if need.bedroomsMin > 0 || need.bedroomsMax > 0 {
            if property.bedrooms <= 0 {
                notes.append("户型未填，没有按室数排除")
            } else if (need.bedroomsMin > 0 && property.bedrooms < need.bedroomsMin)
                || (need.bedroomsMax > 0 && property.bedrooms > need.bedroomsMax) {
                hardFail = true
                notes.append("户型不在要求范围内")
            } else {
                notes.append("户型符合")
            }
        }

        if need.areaMin > 0 || need.areaMax > 0 {
            if property.area <= 0 {
                notes.append("面积未填，没有按面积排除")
            } else if (need.areaMin > 0 && property.area < need.areaMin)
                || (need.areaMax > 0 && property.area > need.areaMax) {
                hardFail = true
                notes.append("面积不在要求范围内")
            } else {
                notes.append("面积符合")
            }
        }

        if need.mustHaveFeatures.contains(FeatureToken.elevator) {
            if property.hasElevator {
                notes.append("电梯必须：有电梯")
            } else {
                hardFail = true
                notes.append("电梯必须：这套没有电梯")
            }
        }
        if need.excludedFeatures.contains(FeatureToken.elevator) {
            if property.hasElevator {
                hardFail = true
                notes.append("已排除电梯，但这套有电梯")
            } else {
                notes.append("电梯排除：没有电梯")
            }
        }
        if need.mustHaveFeatures.contains(FeatureToken.parking) {
            if property.features.contains(FeatureToken.parkingIncluded) {
                notes.append("车位必须：包车位")
            } else if property.features.contains(FeatureToken.parkingNone) {
                hardFail = true
                notes.append("车位必须：这套无车位")
            } else {
                notes.append("车位未填，没有排除")
            }
        }
        if need.excludedFeatures.contains(FeatureToken.parking) && property.features.contains(FeatureToken.parkingIncluded) {
            hardFail = true
            notes.append("已排除车位，但这套包车位")
        }

        let extras = need.mustHaveFeatures.filter { $0 != FeatureToken.elevator && $0 != FeatureToken.parking }
        for feature in extras {
            if property.features.contains(feature) {
                notes.append("必须项「\(feature)」已包含")
            } else {
                hardFail = true
                notes.append("缺少必须项「\(feature)」")
            }
        }
        let banned = need.excludedFeatures.filter { $0 != FeatureToken.elevator && $0 != FeatureToken.parking }
        for feature in banned where property.features.contains(feature) {
            hardFail = true
            notes.append("含有排除项「\(feature)」")
        }

        if !property.status.isListed && !property.status.needsReview {
            hardFail = true
            notes.append("当前状态是\(property.statusTitle)，不在可看范围")
        }

        let bucket: MatchBucket
        if hardFail {
            bucket = .excluded
            if rejected { notes.append("此前带看标记为不考虑") }
        } else if rejected {
            bucket = .previouslyRejected
            notes.append("此前带看标记为不考虑")
        } else if property.status.needsReview {
            bucket = .needsVerification
            notes.append("房源仍是\(property.statusTitle)")
        } else {
            bucket = .qualified
        }

        return MatchRow(
            id: property.id,
            title: "\(property.communityName) \(property.doorText)",
            subtitle: "\(property.layoutText) · \(property.areaText) · \(Money.priceText(property.askingPriceCents, kind: property.listingKind))",
            bucket: bucket,
            notes: notes,
            propertyID: property.id,
            needID: need.id
        )
    }
}

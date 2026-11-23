import Foundation

enum PropertyService {
    static func matches(tab: PropertyBrowseTab, property: Property, filter: PropertyBrowseFilter, query: String) -> Bool {
        if property.browseTab != tab { return false }
        if property.isArchived && !filter.includeArchived { return false }
        if let communityID = filter.communityID, property.community?.id != communityID { return false }
        if !filter.district.isEmpty, property.community?.district != filter.district { return false }
        if let status = filter.status, property.status != status { return false }
        if let bedrooms = filter.bedrooms, property.bedrooms != bedrooms { return false }
        if filter.elevatorOnly && !property.hasElevator { return false }
        if filter.photosOnly && property.photos.isEmpty { return false }
        if filter.recentOnly {
            let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            if property.updatedAt < cutoff { return false }
        }
        if let min = filter.priceMin, property.askingPriceCents < min { return false }
        if let max = filter.priceMax, max > 0, property.askingPriceCents > max { return false }
        if !filter.building.isEmpty && !property.building.localizedCaseInsensitiveContains(filter.building) { return false }
        if !filter.unit.isEmpty && !property.unit.localizedCaseInsensitiveContains(filter.unit) { return false }
        if !filter.room.isEmpty && !property.room.localizedCaseInsensitiveContains(filter.room) { return false }
        let text = BusinessRules.trimmed(query)
        if !text.isEmpty {
            let haystack = [property.building, property.unit, property.room, property.communityName, property.community?.district ?? ""]
                .joined(separator: " ")
            if !haystack.localizedCaseInsensitiveContains(text) { return false }
        }
        return true
    }

    static func sort(_ properties: [Property], by sort: PropertyBrowseSort) -> [Property] {
        switch sort {
        case .newest:
            return properties.sorted { $0.updatedAt > $1.updatedAt }
        case .priceAscending:
            return properties.sorted { lhs, rhs in
                let left = lhs.askingPriceCents == 0 ? Int.max : lhs.askingPriceCents
                let right = rhs.askingPriceCents == 0 ? Int.max : rhs.askingPriceCents
                return left < right
            }
        case .priceDescending:
            return properties.sorted { $0.askingPriceCents > $1.askingPriceCents }
        case .areaDescending:
            return properties.sorted { $0.area > $1.area }
        }
    }

    struct Section: Identifiable {
        var id: String { title }
        var title: String
        var subtitle: String
        var properties: [Property]
    }

    static func sections(_ properties: [Property]) -> [Section] {
        let grouped = Dictionary(grouping: properties) { property in
            property.community?.id.uuidString ?? "none"
        }
        return grouped.values.compactMap { items -> Section? in
            guard let first = items.first else { return nil }
            let title = first.community?.name ?? "未选小区"
            let district = first.community?.district ?? ""
            return Section(title: title, subtitle: district, properties: items)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    static func recordStatusChange(
        of property: Property,
        to newStatus: PropertyStatus,
        reason: String,
        relatedDealID: UUID? = nil
    ) {
        let previous = property.status
        guard previous != newStatus else { return }
        let event = PropertyStatusEvent(
            reason: reason,
            relatedDealID: relatedDealID,
            from: previous,
            to: newStatus
        )
        event.property = property
        property.status = newStatus
        if previous.needsReview && !newStatus.needsReview {
            property.lastVerifiedAt = Date()
        }
        property.updatedAt = Date()
    }
}

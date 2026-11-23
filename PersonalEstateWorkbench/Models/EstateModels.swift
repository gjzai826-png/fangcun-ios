import Foundation
import SwiftData

@Model
final class Community {
    var id: UUID = UUID()
    var name: String = ""
    var aliases: [String] = []
    var district: String = ""
    var address: String = ""
    var latitude: Double?
    var longitude: Double?
    var notes: String = ""
    var isArchived: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Property.community)
    var properties: [Property] = []

    @Relationship(deleteRule: .nullify, inverse: \MarketComparable.community)
    var comparables: [MarketComparable] = []

    init(
        id: UUID = UUID(),
        name: String,
        aliases: [String] = [],
        district: String = "",
        address: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        notes: String = "",
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.district = district
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.notes = notes
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var aliasText: String {
        aliases.joined(separator: "、")
    }
}

@Model
final class Contact {
    var id: UUID = UUID()
    var displayName: String = ""
    var phone: String = ""
    var wechat: String = ""
    var rolesRaw: String = ""
    var notes: String = ""
    var isArchived: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Property.owner)
    var ownedProperties: [Property] = []

    @Relationship(deleteRule: .cascade, inverse: \ClientNeed.contact)
    var clientNeeds: [ClientNeed] = []

    @Relationship(deleteRule: .nullify, inverse: \FollowUp.contact)
    var followUps: [FollowUp] = []

    @Relationship(deleteRule: .nullify, inverse: \Deal.contact)
    var deals: [Deal] = []

    init(
        id: UUID = UUID(),
        displayName: String,
        phone: String = "",
        wechat: String = "",
        roles: [ContactRole] = [],
        notes: String = "",
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.phone = phone
        self.wechat = wechat
        self.rolesRaw = roles.map(\.rawValue).joined(separator: ",")
        self.notes = notes
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var roles: [ContactRole] {
        get {
            rolesRaw.split(separator: ",").compactMap { ContactRole(rawValue: String($0)) }
        }
        set {
            rolesRaw = newValue.map(\.rawValue).joined(separator: ",")
        }
    }

    var roleTitle: String {
        let titles = roles.map(\.title)
        return titles.isEmpty ? "未标角色" : titles.joined(separator: "、")
    }

    var isOwner: Bool {
        roles.contains(.owner) || !ownedProperties.isEmpty
    }
}

@Model
final class Property {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isArchived: Bool = false
    var building: String = ""
    var unit: String = ""
    var room: String = ""
    var listingKindRaw: String = ListingKind.sale.rawValue
    var statusRaw: String = PropertyStatus.needsVerification.rawValue
    var askingPriceCents: Int = 0
    var availableFrom: Date?
    var viewingMethod: String = ""
    var bedrooms: Int = 0
    var livingRooms: Int = 0
    var bathrooms: Int = 0
    var area: Double = 0
    var floor: Int = 0
    var totalFloors: Int = 0
    var orientation: String = ""
    var decoration: String = ""
    var hasElevator: Bool = false
    var features: [String] = []
    var internalNotes: String = ""
    var lastVerifiedAt: Date?
    var materialsVerifiedAt: Date?

    var community: Community?
    var owner: Contact?

    @Relationship(deleteRule: .cascade, inverse: \MediaAsset.property)
    var mediaAssets: [MediaAsset] = []

    @Relationship(deleteRule: .cascade, inverse: \FollowUp.property)
    var followUps: [FollowUp] = []

    @Relationship(deleteRule: .nullify, inverse: \Deal.property)
    var deals: [Deal] = []

    @Relationship(deleteRule: .cascade, inverse: \PropertyStatusEvent.property)
    var statusEvents: [PropertyStatusEvent] = []

    @Relationship(deleteRule: .nullify, inverse: \ViewingItem.property)
    var viewingItems: [ViewingItem] = []

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false,
        building: String = "",
        unit: String = "",
        room: String = "",
        listingKind: ListingKind = .sale,
        status: PropertyStatus = .needsVerification,
        askingPriceCents: Int = 0,
        availableFrom: Date? = nil,
        viewingMethod: String = "",
        bedrooms: Int = 0,
        livingRooms: Int = 0,
        bathrooms: Int = 0,
        area: Double = 0,
        floor: Int = 0,
        totalFloors: Int = 0,
        orientation: String = "",
        decoration: String = "",
        hasElevator: Bool = false,
        features: [String] = [],
        internalNotes: String = "",
        lastVerifiedAt: Date? = nil,
        materialsVerifiedAt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.building = building
        self.unit = unit
        self.room = room
        self.listingKindRaw = listingKind.rawValue
        self.statusRaw = status.rawValue
        self.askingPriceCents = askingPriceCents
        self.availableFrom = availableFrom
        self.viewingMethod = viewingMethod
        self.bedrooms = bedrooms
        self.livingRooms = livingRooms
        self.bathrooms = bathrooms
        self.area = area
        self.floor = floor
        self.totalFloors = totalFloors
        self.orientation = orientation
        self.decoration = decoration
        self.hasElevator = hasElevator
        self.features = features
        self.internalNotes = internalNotes
        self.lastVerifiedAt = lastVerifiedAt
        self.materialsVerifiedAt = materialsVerifiedAt
    }

    var listingKind: ListingKind {
        get { ListingKind(rawValue: listingKindRaw) ?? .sale }
        set { listingKindRaw = newValue.rawValue }
    }

    var status: PropertyStatus {
        get { PropertyStatus(rawValue: statusRaw) ?? .unknown }
        set { statusRaw = newValue.rawValue }
    }

    var statusTitle: String { status.title(for: listingKind) }

    var browseTab: PropertyBrowseTab {
        if listingKind == .sale && status.isListed { return .sale }
        if listingKind == .rent && status.isListed { return .rent }
        return .unlisted
    }

    var canRegisterDeal: Bool {
        !isArchived && (status == .available || status == .reserved || status.needsReview)
    }

    var layoutText: String {
        if bedrooms == 0 && livingRooms == 0 && bathrooms == 0 { return "户型未填" }
        return "\(bedrooms)室\(livingRooms)厅\(bathrooms)卫"
    }

    var doorText: String {
        var parts: [String] = []
        if !building.isEmpty { parts.append("\(building)幢") }
        if !unit.isEmpty { parts.append("\(unit)单元") }
        if !room.isEmpty { parts.append(room) }
        return parts.isEmpty ? "门牌未填" : parts.joined()
    }

    var areaText: String {
        area > 0 ? area.formatted(.number.precision(.fractionLength(0...2))) + "㎡" : "面积未填"
    }

    var floorText: String {
        if floor > 0 && totalFloors > 0 { return "\(floor)/\(totalFloors)层" }
        if floor > 0 { return "\(floor)层" }
        if totalFloors > 0 { return "共\(totalFloors)层" }
        return ""
    }

    var communityName: String { community?.name ?? "未选小区" }

    var photos: [MediaAsset] {
        mediaAssets.filter { $0.kind == .photo }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var videos: [MediaAsset] {
        mediaAssets.filter { $0.kind == .video }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var shareFeatures: [String] {
        var items = features
        if hasElevator { items.append("有电梯") }
        return items
    }
}

@Model
final class MediaAsset {
    var id: UUID = UUID()
    var kindRaw: String = MediaKind.photo.rawValue
    var relativePath: String = ""
    var thumbnailRelativePath: String = ""
    var originalFilename: String = ""
    var mimeType: String = ""
    var fileSize: Int = 0
    var caption: String = ""
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    var property: Property?
    var comparable: MarketComparable?

    init(
        id: UUID = UUID(),
        kind: MediaKind,
        relativePath: String,
        thumbnailRelativePath: String = "",
        originalFilename: String = "",
        mimeType: String = "",
        fileSize: Int = 0,
        caption: String = "",
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.relativePath = relativePath
        self.thumbnailRelativePath = thumbnailRelativePath
        self.originalFilename = originalFilename
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.caption = caption
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    var kind: MediaKind {
        get { MediaKind(rawValue: kindRaw) ?? .photo }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
final class PropertyStatusEvent {
    var id: UUID = UUID()
    var occurredAt: Date = Date()
    var reason: String = ""
    var relatedDealID: UUID?
    var fromRaw: String = ""
    var toRaw: String = ""

    var property: Property?

    init(
        id: UUID = UUID(),
        occurredAt: Date = Date(),
        reason: String,
        relatedDealID: UUID? = nil,
        from: PropertyStatus,
        to: PropertyStatus
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.reason = reason
        self.relatedDealID = relatedDealID
        self.fromRaw = from.rawValue
        self.toRaw = to.rawValue
    }

    func title(for kind: ListingKind) -> String {
        let from = PropertyStatus(rawValue: fromRaw)?.title(for: kind) ?? fromRaw
        let to = PropertyStatus(rawValue: toRaw)?.title(for: kind) ?? toRaw
        return "\(from) → \(to)"
    }
}

@Model
final class ClientNeed {
    var id: UUID = UUID()
    var kindRaw: String = NeedKind.buy.rawValue
    var statusRaw: String = NeedStatus.active.rawValue
    var urgencyRaw: String = Urgency.normal.rawValue
    var budgetMinCents: Int = 0
    var budgetMaxCents: Int = 0
    var preferredDistricts: [String] = []
    var preferredCommunityIDs: [UUID] = []
    var bedroomsMin: Int = 0
    var bedroomsMax: Int = 0
    var areaMin: Double = 0
    var areaMax: Double = 0
    var moveInDate: Date?
    var mustHaveFeatures: [String] = []
    var excludedFeatures: [String] = []
    var preferencesNote: String = ""
    var source: String = ""
    var closedReason: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var contact: Contact?

    @Relationship(deleteRule: .cascade, inverse: \FollowUp.clientNeed)
    var followUps: [FollowUp] = []

    @Relationship(deleteRule: .cascade, inverse: \Viewing.clientNeed)
    var viewings: [Viewing] = []

    @Relationship(deleteRule: .nullify, inverse: \Deal.clientNeed)
    var deals: [Deal] = []

    init(
        id: UUID = UUID(),
        kind: NeedKind = .buy,
        status: NeedStatus = .active,
        urgency: Urgency = .normal,
        budgetMinCents: Int = 0,
        budgetMaxCents: Int = 0,
        preferredDistricts: [String] = [],
        preferredCommunityIDs: [UUID] = [],
        bedroomsMin: Int = 0,
        bedroomsMax: Int = 0,
        areaMin: Double = 0,
        areaMax: Double = 0,
        moveInDate: Date? = nil,
        mustHaveFeatures: [String] = [],
        excludedFeatures: [String] = [],
        preferencesNote: String = "",
        source: String = "",
        closedReason: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.statusRaw = status.rawValue
        self.urgencyRaw = urgency.rawValue
        self.budgetMinCents = budgetMinCents
        self.budgetMaxCents = budgetMaxCents
        self.preferredDistricts = preferredDistricts
        self.preferredCommunityIDs = preferredCommunityIDs
        self.bedroomsMin = bedroomsMin
        self.bedroomsMax = bedroomsMax
        self.areaMin = areaMin
        self.areaMax = areaMax
        self.moveInDate = moveInDate
        self.mustHaveFeatures = mustHaveFeatures
        self.excludedFeatures = excludedFeatures
        self.preferencesNote = preferencesNote
        self.source = source
        self.closedReason = closedReason
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var kind: NeedKind {
        get { NeedKind(rawValue: kindRaw) ?? .buy }
        set { kindRaw = newValue.rawValue }
    }

    var status: NeedStatus {
        get { NeedStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var urgency: Urgency {
        get { Urgency(rawValue: urgencyRaw) ?? .normal }
        set { urgencyRaw = newValue.rawValue }
    }

    var budgetText: String {
        let kind = self.kind
        let min = budgetMinCents
        let max = budgetMaxCents
        func text(_ cents: Int) -> String {
            kind == .rent ? Money.yuanText(cents) + "元" : Money.saleText(cents)
        }
        if min > 0 && max > 0 { return "\(text(min))–\(text(max))" }
        if max > 0 { return "\(text(max))以内" }
        if min > 0 { return "\(text(min))起" }
        return "预算不限"
    }
}

@Model
final class FollowUp {
    var id: UUID = UUID()
    var channelRaw: String = FollowUpChannel.call.rawValue
    var content: String = ""
    var outcome: String = ""
    var nextAction: String = ""
    var nextDueAt: Date?
    var occurredAt: Date = Date()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var clientNeed: ClientNeed?
    var contact: Contact?
    var property: Property?

    init(
        id: UUID = UUID(),
        channel: FollowUpChannel = .call,
        content: String,
        outcome: String = "",
        nextAction: String = "",
        nextDueAt: Date? = nil,
        occurredAt: Date = Date()
    ) {
        self.id = id
        self.channelRaw = channel.rawValue
        self.content = content
        self.outcome = outcome
        self.nextAction = nextAction
        self.nextDueAt = nextDueAt
        self.occurredAt = occurredAt
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var channel: FollowUpChannel {
        get { FollowUpChannel(rawValue: channelRaw) ?? .call }
        set { channelRaw = newValue.rawValue }
    }
}

@Model
final class Viewing {
    var id: UUID = UUID()
    var scheduledStart: Date = Date()
    var scheduledEnd: Date = Date()
    var meetingPoint: String = ""
    var notes: String = ""
    var statusRaw: String = ViewingStatus.scheduled.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var clientNeed: ClientNeed?

    @Relationship(deleteRule: .cascade, inverse: \ViewingItem.viewing)
    var items: [ViewingItem] = []

    init(
        id: UUID = UUID(),
        scheduledStart: Date,
        scheduledEnd: Date,
        meetingPoint: String = "",
        notes: String = "",
        status: ViewingStatus = .scheduled
    ) {
        self.id = id
        self.scheduledStart = scheduledStart
        self.scheduledEnd = scheduledEnd
        self.meetingPoint = meetingPoint
        self.notes = notes
        self.statusRaw = status.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var status: ViewingStatus {
        get { ViewingStatus(rawValue: statusRaw) ?? .scheduled }
        set { statusRaw = newValue.rawValue }
    }

    var sortedItems: [ViewingItem] {
        items.sorted { $0.sortOrder < $1.sortOrder }
    }
}

@Model
final class ViewingItem {
    var id: UUID = UUID()
    var sortOrder: Int = 0
    var feedback: String = ""
    var interestRaw: String = ViewingInterest.neutral.rawValue
    var objections: String = ""

    var viewing: Viewing?
    var property: Property?

    init(
        id: UUID = UUID(),
        sortOrder: Int = 0,
        feedback: String = "",
        interest: ViewingInterest = .neutral,
        objections: String = ""
    ) {
        self.id = id
        self.sortOrder = sortOrder
        self.feedback = feedback
        self.interestRaw = interest.rawValue
        self.objections = objections
    }

    var interest: ViewingInterest {
        get { ViewingInterest(rawValue: interestRaw) ?? .neutral }
        set { interestRaw = newValue.rawValue }
    }
}

@Model
final class Deal {
    var id: UUID = UUID()
    var kindRaw: String = DealKind.sale.rawValue
    var statusRaw: String = DealStatus.active.rawValue
    var signedOn: Date = Date()
    var actualPriceCents: Int = 0
    var commissionReceivableCents: Int = 0
    var commissionReceivedCents: Int = 0
    var leaseStartOn: Date?
    var leaseEndOn: Date?
    var communityNameSnapshot: String = ""
    var propertyDescriptionSnapshot: String = ""
    var counterpartyNameSnapshot: String = ""
    var notes: String = ""
    var voidReason: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var property: Property?
    var contact: Contact?
    var clientNeed: ClientNeed?

    @Relationship(deleteRule: .cascade, inverse: \DealCommissionAllocation.deal)
    var commissionAllocation: DealCommissionAllocation?

    init(
        id: UUID = UUID(),
        kind: DealKind,
        status: DealStatus = .active,
        signedOn: Date = Date(),
        actualPriceCents: Int,
        commissionReceivableCents: Int = 0,
        commissionReceivedCents: Int = 0,
        leaseStartOn: Date? = nil,
        leaseEndOn: Date? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.statusRaw = status.rawValue
        self.signedOn = signedOn
        self.actualPriceCents = actualPriceCents
        self.commissionReceivableCents = commissionReceivableCents
        self.commissionReceivedCents = commissionReceivedCents
        self.leaseStartOn = leaseStartOn
        self.leaseEndOn = leaseEndOn
        self.notes = notes
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var kind: DealKind {
        get { DealKind(rawValue: kindRaw) ?? .sale }
        set { kindRaw = newValue.rawValue }
    }

    var status: DealStatus {
        get { DealStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    var priceText: String {
        kind == .sale ? Money.saleText(actualPriceCents) : Money.rentText(actualPriceCents)
    }

    var displayNumber: String {
        String(id.uuidString.prefix(8)).uppercased()
    }
}

@Model
final class DealCommissionAllocation {
    var id: UUID = UUID()
    var propertyFee: Bool = false
    var photoFee: Bool = false
    var keyFee: Bool = false
    var followUpPercent: Int = 0

    var deal: Deal?

    init(
        id: UUID = UUID(),
        propertyFee: Bool = false,
        photoFee: Bool = false,
        keyFee: Bool = false,
        followUpPercent: Int = 0
    ) {
        self.id = id
        self.propertyFee = propertyFee
        self.photoFee = photoFee
        self.keyFee = keyFee
        self.followUpPercent = followUpPercent
    }
}

@Model
final class MarketComparable {
    var id: UUID = UUID()
    var kindRaw: String = ListingKind.sale.rawValue
    var dealDate: Date = Date()
    var priceCents: Int = 0
    var area: Double = 0
    var bedrooms: Int = 0
    var decoration: String = ""
    var floorDescription: String = ""
    var sourceDescription: String = ""
    var evidenceAssetID: UUID?
    var notes: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var community: Community?

    @Relationship(deleteRule: .cascade, inverse: \MediaAsset.comparable)
    var evidenceAssets: [MediaAsset] = []

    init(
        id: UUID = UUID(),
        kind: ListingKind = .sale,
        dealDate: Date = Date(),
        priceCents: Int,
        area: Double = 0,
        bedrooms: Int = 0,
        decoration: String = "",
        floorDescription: String = "",
        sourceDescription: String,
        evidenceAssetID: UUID? = nil,
        notes: String = ""
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.dealDate = dealDate
        self.priceCents = priceCents
        self.area = area
        self.bedrooms = bedrooms
        self.decoration = decoration
        self.floorDescription = floorDescription
        self.sourceDescription = sourceDescription
        self.evidenceAssetID = evidenceAssetID
        self.notes = notes
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var kind: ListingKind {
        get { ListingKind(rawValue: kindRaw) ?? .sale }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
final class TaskItem {
    var id: UUID = UUID()
    var kindRaw: String = TaskKind.manual.rawValue
    var stateRaw: String = TaskState.open.rawValue
    var title: String = ""
    var notes: String = ""
    var dueAt: Date = Date()
    var completedAt: Date?
    var sourceID: UUID?
    var sourceKey: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        id: UUID = UUID(),
        kind: TaskKind,
        state: TaskState = .open,
        title: String,
        notes: String = "",
        dueAt: Date,
        completedAt: Date? = nil,
        sourceID: UUID? = nil,
        sourceKey: String = ""
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.stateRaw = state.rawValue
        self.title = title
        self.notes = notes
        self.dueAt = dueAt
        self.completedAt = completedAt
        self.sourceID = sourceID
        self.sourceKey = sourceKey
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var kind: TaskKind {
        get { TaskKind(rawValue: kindRaw) ?? .manual }
        set { kindRaw = newValue.rawValue }
    }

    var state: TaskState {
        get { TaskState(rawValue: stateRaw) ?? .open }
        set { stateRaw = newValue.rawValue }
    }
}

@Model
final class WorkspaceRecord {
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date()

    init(id: UUID = UUID(), title: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
    }
}

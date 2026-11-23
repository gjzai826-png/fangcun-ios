import CryptoKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

extension UTType {
    static let estateBackup = UTType(
        exportedAs: "com.example.personal-estate-workbench.backup",
        conformingTo: .package
    )
}

enum PortabilityError: LocalizedError {
    case invalid([String])
    case unreadable

    var errorDescription: String? {
        switch self {
        case .invalid(let errors):
            return errors.prefix(8).joined(separator: "\n")
        case .unreadable:
            return "打不开这份备份。"
        }
    }
}

struct EstateBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.estateBackup] }
    var packageURL: URL

    init(packageURL: URL) {
        self.packageURL = packageURL
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: packageURL, options: .immediate)
    }
}

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data(text.utf8))
        return FileWrapper(regularFileWithContents: data)
    }
}

struct BackupValidation {
    var errors: [String]
    var file: BackupFile?
}

@MainActor
enum DataPortabilityService {
    static let format = "com.example.personal-estate-workbench.backup"

    static func exportPackage(context: ModelContext) throws -> URL {
        let file = try makeFile(context: context)
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("方寸备份-\(stamp()).estatebackup", isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
        let mediaDir = folder.appendingPathComponent("media", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        var exported = file
        exported.media = try file.media.map { item in
            var copy = item
            copy.sha256 = try copyIntoPackage(item.packagePath, mediaDir: mediaDir, sourceRelative: item.storedName)
            if !item.thumbnailStoredName.isEmpty {
                copy.thumbnailSha256 = try copyIntoPackage(item.thumbnailPackagePath, mediaDir: mediaDir, sourceRelative: item.thumbnailStoredName)
            }
            return copy
        }
        let data = try encoder().encode(exported)
        try data.write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
        return folder
    }

    static func validate(package url: URL) throws -> BackupValidation {
        let manifest = url.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifest.path) else {
            return BackupValidation(errors: ["找不到 manifest.json。请选择未加密的 .estatebackup 包。"], file: nil)
        }
        let data = try Data(contentsOf: manifest)
        let file: BackupFile
        do {
            file = try decoder().decode(BackupFile.self, from: data)
        } catch {
            return BackupValidation(errors: ["清单无法解析，或不是这一版备份。"], file: nil)
        }
        var errors: [String] = []
        if file.format != format { errors.append("备份格式不符。") }
        if file.formatVersion != EstateSchema.version { errors.append("备份版本是 \(file.formatVersion)，当前只接受 \(EstateSchema.version)。") }
        if file.encrypted { errors.append("这份备份标记为已加密，当前版本只读取未加密备份。") }

        let communityIDs = Set(file.communities.map(\.id))
        let contactIDs = Set(file.contacts.map(\.id))
        let propertyIDs = Set(file.properties.map(\.id))
        let needIDs = Set(file.clientNeeds.map(\.id))
        let comparableIDs = Set(file.comparables.map(\.id))
        let dealIDs = Set(file.deals.map(\.id))
        func unique(_ label: String, _ ids: [UUID]) {
            if Set(ids).count != ids.count { errors.append("\(label)里有重复编号。") }
        }
        unique("小区", file.communities.map(\.id))
        unique("联系人", file.contacts.map(\.id))
        unique("房源", file.properties.map(\.id))
        unique("媒体", file.media.map(\.id))
        for community in file.communities where BusinessRules.trimmed(community.name).isEmpty {
            errors.append("有小区缺少全名。")
        }
        for property in file.properties {
            if let id = property.communityID, !communityIDs.contains(id) { errors.append("房源关联了不存在的小区。") }
            if property.communityID == nil { errors.append("有房源没有小区。") }
            if let id = property.ownerID, !contactIDs.contains(id) { errors.append("房源关联了不存在的业主。") }
        }
        var total: Int64 = 0
        for media in file.media {
            let parents = [media.propertyID, media.comparableID].compactMap { $0 }
            if parents.count != 1 { errors.append("媒体必须且只能关联一个业务对象。") }
            if let id = media.propertyID, !propertyIDs.contains(id) { errors.append("照片或视频关联了不存在的房源。") }
            if let id = media.comparableID, !comparableIDs.contains(id) { errors.append("行情证据关联了不存在的记录。") }
            total += try checkFile(url.appendingPathComponent(media.packagePath), expectedSize: media.fileSize, expectedHash: media.sha256, errors: &errors)
            if !media.thumbnailPackagePath.isEmpty {
                _ = try checkFile(url.appendingPathComponent(media.thumbnailPackagePath), expectedSize: nil, expectedHash: media.thumbnailSha256, errors: &errors)
            }
        }
        if total > BusinessRules.maxMediaTotalBytes { errors.append("媒体合计超过 16 GB。") }
        for item in file.clientNeeds {
            if let id = item.contactID, !contactIDs.contains(id) { errors.append("需求关联了不存在的联系人。") }
        }
        for item in file.followUps {
            if item.clientNeedID == nil && item.contactID == nil && item.propertyID == nil {
                errors.append("有跟进没有关联需求、房源或联系人。")
            }
            if let id = item.clientNeedID, !needIDs.contains(id) { errors.append("跟进关联了不存在的需求。") }
            if let id = item.propertyID, !propertyIDs.contains(id) { errors.append("跟进关联了不存在的房源。") }
            if let needID = item.clientNeedID, let contactID = item.contactID,
               let need = file.clientNeeds.first(where: { $0.id == needID }),
               let needContact = need.contactID, needContact != contactID {
                errors.append("跟进的联系人和需求不一致。")
            }
        }
        for viewing in file.viewings {
            if let id = viewing.clientNeedID, !needIDs.contains(id) { errors.append("带看关联了不存在的需求。") }
            if viewing.scheduledEnd < viewing.scheduledStart { errors.append("有带看的结束时间早于开始。") }
            let items = file.viewingItems.filter { $0.viewingID == viewing.id }
            if items.isEmpty { errors.append("有带看没有房源。") }
            if Set(items.compactMap(\.propertyID)).count != items.compactMap(\.propertyID).count {
                errors.append("同一次带看重复了房源。")
            }
        }
        for item in file.viewingItems {
            if let id = item.propertyID, !propertyIDs.contains(id) { errors.append("带看条目关联了不存在的房源。") }
        }
        for deal in file.deals {
            if let id = deal.propertyID, !propertyIDs.contains(id) { errors.append("成交关联了不存在的房源。") }
            if let propertyID = deal.propertyID, let property = file.properties.first(where: { $0.id == propertyID }) {
                let kind = DealKind(rawValue: deal.kindRaw)
                let listing = ListingKind(rawValue: property.listingKindRaw)
                if kind?.listingKind != listing { errors.append("有成交类型和房源租售类型不一致。") }
            }
        }
        for item in file.allocations where !dealIDs.contains(item.dealID) {
            errors.append("佣金记录关联了不存在的成交。")
        }
        for item in file.comparables {
            if item.priceCents <= 0 { errors.append("有行情价格不是正数。") }
            if BusinessRules.trimmed(item.sourceDescription).isEmpty { errors.append("有行情没有来源。") }
            if let id = item.communityID, !communityIDs.contains(id) { errors.append("行情关联了不存在的小区。") }
        }
        for item in file.statusEvents {
            if !propertyIDs.contains(item.propertyID) { errors.append("状态历史关联了不存在的房源。") }
            if PropertyStatus(rawValue: item.fromRaw) == nil || PropertyStatus(rawValue: item.toRaw) == nil {
                errors.append("状态历史里有无法识别的枚举。")
            }
            if let id = item.relatedDealID, !dealIDs.contains(id) { errors.append("状态历史关联了不存在的成交。") }
        }
        return BackupValidation(errors: errors, file: errors.isEmpty ? file : nil)
    }

    static func restore(from package: URL, context: ModelContext) throws {
        let started = package.startAccessingSecurityScopedResource()
        defer { if started { package.stopAccessingSecurityScopedResource() } }
        let report = try validate(package: package)
        guard report.errors.isEmpty, let file = report.file else {
            throw PortabilityError.invalid(report.errors)
        }
        _ = try makeSafetyBackup(context: context)
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("media-staging-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        for media in file.media {
            try FileManager.default.copyItem(
                at: package.appendingPathComponent(media.packagePath),
                to: staging.appendingPathComponent(media.storedName)
            )
            if !media.thumbnailStoredName.isEmpty {
                try? FileManager.default.copyItem(
                    at: package.appendingPathComponent(media.thumbnailPackagePath),
                    to: staging.appendingPathComponent(media.thumbnailStoredName)
                )
            }
        }
        try wipe(context)
        try insert(file, into: context)
        try MediaStore.replaceRoot(with: staging)
        try context.save()
    }

    static func makeSafetyBackup(context: ModelContext) throws -> URL {
        let package = try exportPackage(context: context)
        let destFolder = try safetyDirectory()
        let dest = destFolder.appendingPathComponent(package.lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: package, to: dest)
        pruneSafetyBackups(in: destFolder, keeping: 3)
        return dest
    }

    static func safetyBackups() -> [URL] {
        guard let folder = try? safetyDirectory() else { return [] }
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return urls.filter { $0.pathExtension == "estatebackup" }.sorted {
            let left = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return left > right
        }
    }

    static func csv(_ kind: CSVExportKind, context: ModelContext) throws -> String {
        switch kind {
        case .communities:
            return table(
                ["编号", "名称", "别名", "区域", "地址", "纬度", "经度", "备注", "已归档"],
                try context.all(Community.self).map {
                    [s($0.id), $0.name, $0.aliasText, $0.district, $0.address, n($0.latitude), n($0.longitude), $0.notes, b($0.isArchived)]
                }
            )
        case .contacts:
            return table(
                ["编号", "称呼", "电话", "微信", "角色", "备注", "已归档"],
                try context.all(Contact.self).map {
                    [s($0.id), $0.displayName, $0.phone, $0.wechat, $0.roleTitle, $0.notes, b($0.isArchived)]
                }
            )
        case .properties:
            return table(
                ["编号", "小区", "区域", "楼栋", "单元", "房号", "租售", "状态", "报价人民币分", "报价显示", "面积", "室", "厅", "卫", "楼层", "总层", "朝向", "装修", "电梯", "特征", "可入住", "看房方式", "已归档"],
                try context.all(Property.self).map {
                    [
                        s($0.id), $0.communityName, $0.community?.district ?? "", $0.building, $0.unit, $0.room,
                        $0.listingKind.rawValue, $0.status.rawValue, String($0.askingPriceCents),
                        Money.priceText($0.askingPriceCents, kind: $0.listingKind), String($0.area),
                        String($0.bedrooms), String($0.livingRooms), String($0.bathrooms),
                        String($0.floor), String($0.totalFloors), $0.orientation, $0.decoration,
                        b($0.hasElevator), $0.features.joined(separator: "、"),
                        $0.availableFrom.map(CNDate.day) ?? "", $0.viewingMethod, b($0.isArchived)
                    ]
                }
            )
        case .clientNeeds:
            return table(
                ["编号", "联系人", "类型", "状态", "紧急", "预算下限人民币分", "预算上限人民币分", "预算显示", "区域", "室起", "室止", "来源", "关闭原因"],
                try context.all(ClientNeed.self).map {
                    [
                        s($0.id), $0.contact?.displayName ?? "", $0.kind.rawValue, $0.status.rawValue, $0.urgency.rawValue,
                        String($0.budgetMinCents), String($0.budgetMaxCents), $0.budgetText,
                        $0.preferredDistricts.joined(separator: "、"), String($0.bedroomsMin), String($0.bedroomsMax),
                        $0.source, $0.closedReason
                    ]
                }
            )
        case .followUps:
            return table(
                ["编号", "渠道", "内容", "结果", "下一步", "下次联系", "发生时间"],
                try context.all(FollowUp.self).map {
                    [$0.channel.rawValue, $0.content, $0.outcome, $0.nextAction, $0.nextDueAt.map(CNDate.dayTime) ?? "", CNDate.dayTime($0.occurredAt)].prepending(s($0.id))
                }
            )
        case .viewings:
            return table(
                ["编号", "开始", "结束", "见面地点", "状态", "备注"],
                try context.all(Viewing.self).map {
                    [s($0.id), CNDate.dayTime($0.scheduledStart), CNDate.dayTime($0.scheduledEnd), $0.meetingPoint, $0.status.rawValue, $0.notes]
                }
            )
        case .deals:
            return table(
                ["编号", "类型", "状态", "签约日期", "成交价人民币分", "成交价显示", "应收佣金人民币分", "已收佣金人民币分", "租约开始", "租约结束", "小区快照", "房源快照", "对方快照", "作废原因"],
                try context.all(Deal.self).map {
                    [
                        s($0.id), $0.kind.rawValue, $0.status.rawValue, CNDate.day($0.signedOn),
                        String($0.actualPriceCents), $0.priceText,
                        String($0.commissionReceivableCents), String($0.commissionReceivedCents),
                        $0.leaseStartOn.map(CNDate.day) ?? "", $0.leaseEndOn.map(CNDate.day) ?? "",
                        $0.communityNameSnapshot, $0.propertyDescriptionSnapshot, $0.counterpartyNameSnapshot, $0.voidReason
                    ]
                }
            )
        case .comparables:
            return table(
                ["编号", "小区", "类型", "日期", "价格人民币分", "价格显示", "面积", "室", "装修", "楼层描述", "来源", "备注"],
                try context.all(MarketComparable.self).map {
                    [
                        s($0.id), $0.community?.name ?? "", $0.kind.rawValue, CNDate.day($0.dealDate),
                        String($0.priceCents), Money.priceText($0.priceCents, kind: $0.kind),
                        String($0.area), String($0.bedrooms), $0.decoration, $0.floorDescription, $0.sourceDescription, $0.notes
                    ]
                }
            )
        case .tasks:
            return table(
                ["编号", "类型", "状态", "标题", "备注", "到期", "完成时间"],
                try context.all(TaskItem.self).map {
                    [s($0.id), $0.kind.rawValue, $0.state.rawValue, $0.title, $0.notes, CNDate.dayTime($0.dueAt), $0.completedAt.map(CNDate.dayTime) ?? ""]
                }
            )
        }
    }

    private static func makeFile(context: ModelContext) throws -> BackupFile {
        let workspace = try context.all(WorkspaceRecord.self).first
        return BackupFile(
            format: format,
            formatVersion: EstateSchema.version,
            appVersion: "0.1.0",
            build: "10",
            exportedAt: Date(),
            encrypted: false,
            communities: try context.all(Community.self).map(CommunityDTO.init),
            contacts: try context.all(Contact.self).map(ContactDTO.init),
            properties: try context.all(Property.self).map(PropertyDTO.init),
            media: try context.all(MediaAsset.self).map(MediaDTO.init),
            statusEvents: try context.all(PropertyStatusEvent.self).map(StatusEventDTO.init),
            clientNeeds: try context.all(ClientNeed.self).map(ClientNeedDTO.init),
            followUps: try context.all(FollowUp.self).map(FollowUpDTO.init),
            viewings: try context.all(Viewing.self).map(ViewingDTO.init),
            viewingItems: try context.all(ViewingItem.self).map(ViewingItemDTO.init),
            deals: try context.all(Deal.self).map(DealDTO.init),
            allocations: try context.all(DealCommissionAllocation.self).compactMap(AllocationDTO.init),
            comparables: try context.all(MarketComparable.self).map(ComparableDTO.init),
            tasks: try context.all(TaskItem.self).map(TaskDTO.init),
            workspace: workspace.map { WorkspaceDTO(id: $0.id, title: $0.title, createdAt: $0.createdAt) }
        )
    }

    private static func insert(_ file: BackupFile, into context: ModelContext) throws {
        var communities: [UUID: Community] = [:]
        var contacts: [UUID: Contact] = [:]
        var properties: [UUID: Property] = [:]
        var needs: [UUID: ClientNeed] = [:]
        var viewings: [UUID: Viewing] = [:]
        var deals: [UUID: Deal] = [:]
        var comparables: [UUID: MarketComparable] = [:]

        for item in file.communities {
            let model = Community(
                id: item.id, name: item.name, aliases: item.aliases, district: item.district,
                address: item.address, latitude: item.latitude, longitude: item.longitude,
                notes: item.notes, isArchived: item.isArchived, createdAt: item.createdAt, updatedAt: item.updatedAt
            )
            context.insert(model)
            communities[item.id] = model
        }
        for item in file.contacts {
            let model = Contact(
                id: item.id, displayName: item.displayName, phone: item.phone, wechat: item.wechat,
                roles: item.rolesRaw.split(separator: ",").compactMap { ContactRole(rawValue: String($0)) },
                notes: item.notes, isArchived: item.isArchived, createdAt: item.createdAt, updatedAt: item.updatedAt
            )
            context.insert(model)
            contacts[item.id] = model
        }
        for item in file.properties {
            let model = Property(
                id: item.id, createdAt: item.createdAt, updatedAt: item.updatedAt, isArchived: item.isArchived,
                building: item.building, unit: item.unit, room: item.room,
                listingKind: ListingKind(rawValue: item.listingKindRaw) ?? .sale,
                status: PropertyStatus(rawValue: item.statusRaw) ?? .unknown,
                askingPriceCents: item.askingPriceCents, availableFrom: item.availableFrom,
                viewingMethod: item.viewingMethod, bedrooms: item.bedrooms, livingRooms: item.livingRooms,
                bathrooms: item.bathrooms, area: item.area, floor: item.floor, totalFloors: item.totalFloors,
                orientation: item.orientation, decoration: item.decoration, hasElevator: item.hasElevator,
                features: item.features, internalNotes: item.internalNotes,
                lastVerifiedAt: item.lastVerifiedAt, materialsVerifiedAt: item.materialsVerifiedAt
            )
            model.community = item.communityID.flatMap { communities[$0] }
            model.owner = item.ownerID.flatMap { contacts[$0] }
            context.insert(model)
            properties[item.id] = model
        }
        for item in file.comparables {
            let model = MarketComparable(
                id: item.id, kind: ListingKind(rawValue: item.kindRaw) ?? .sale, dealDate: item.dealDate,
                priceCents: item.priceCents, area: item.area, bedrooms: item.bedrooms, decoration: item.decoration,
                floorDescription: item.floorDescription, sourceDescription: item.sourceDescription,
                evidenceAssetID: item.evidenceAssetID, notes: item.notes
            )
            model.createdAt = item.createdAt
            model.updatedAt = item.updatedAt
            model.community = item.communityID.flatMap { communities[$0] }
            context.insert(model)
            comparables[item.id] = model
        }
        for item in file.media {
            let model = MediaAsset(
                id: item.id, kind: MediaKind(rawValue: item.kindRaw) ?? .photo, relativePath: item.storedName,
                thumbnailRelativePath: item.thumbnailStoredName, originalFilename: item.originalFilename,
                mimeType: item.mimeType, fileSize: item.fileSize, caption: item.caption,
                sortOrder: item.sortOrder, createdAt: item.createdAt
            )
            model.property = item.propertyID.flatMap { properties[$0] }
            model.comparable = item.comparableID.flatMap { comparables[$0] }
            context.insert(model)
        }
        for item in file.statusEvents {
            let model = PropertyStatusEvent(
                id: item.id, occurredAt: item.occurredAt, reason: item.reason, relatedDealID: item.relatedDealID,
                from: PropertyStatus(rawValue: item.fromRaw) ?? .unknown,
                to: PropertyStatus(rawValue: item.toRaw) ?? .unknown
            )
            model.property = properties[item.propertyID]
            context.insert(model)
        }
        for item in file.clientNeeds {
            let model = ClientNeed(
                id: item.id, kind: NeedKind(rawValue: item.kindRaw) ?? .buy,
                status: NeedStatus(rawValue: item.statusRaw) ?? .active,
                urgency: Urgency(rawValue: item.urgencyRaw) ?? .normal,
                budgetMinCents: item.budgetMinCents, budgetMaxCents: item.budgetMaxCents,
                preferredDistricts: item.preferredDistricts, preferredCommunityIDs: item.preferredCommunityIDs,
                bedroomsMin: item.bedroomsMin, bedroomsMax: item.bedroomsMax, areaMin: item.areaMin, areaMax: item.areaMax,
                moveInDate: item.moveInDate, mustHaveFeatures: item.mustHaveFeatures, excludedFeatures: item.excludedFeatures,
                preferencesNote: item.preferencesNote, source: item.source, closedReason: item.closedReason,
                createdAt: item.createdAt, updatedAt: item.updatedAt
            )
            model.contact = item.contactID.flatMap { contacts[$0] }
            context.insert(model)
            needs[item.id] = model
        }
        for item in file.followUps {
            let model = FollowUp(
                id: item.id, channel: FollowUpChannel(rawValue: item.channelRaw) ?? .call, content: item.content,
                outcome: item.outcome, nextAction: item.nextAction, nextDueAt: item.nextDueAt, occurredAt: item.occurredAt
            )
            model.createdAt = item.createdAt
            model.updatedAt = item.updatedAt
            model.clientNeed = item.clientNeedID.flatMap { needs[$0] }
            model.contact = item.contactID.flatMap { contacts[$0] }
            model.property = item.propertyID.flatMap { properties[$0] }
            context.insert(model)
        }
        for item in file.viewings {
            let model = Viewing(
                id: item.id, scheduledStart: item.scheduledStart, scheduledEnd: item.scheduledEnd,
                meetingPoint: item.meetingPoint, notes: item.notes,
                status: ViewingStatus(rawValue: item.statusRaw) ?? .scheduled
            )
            model.createdAt = item.createdAt
            model.updatedAt = item.updatedAt
            model.clientNeed = item.clientNeedID.flatMap { needs[$0] }
            context.insert(model)
            viewings[item.id] = model
        }
        for item in file.viewingItems {
            let model = ViewingItem(
                id: item.id, sortOrder: item.sortOrder, feedback: item.feedback,
                interest: ViewingInterest(rawValue: item.interestRaw) ?? .neutral, objections: item.objections
            )
            model.viewing = viewings[item.viewingID]
            model.property = item.propertyID.flatMap { properties[$0] }
            context.insert(model)
        }
        for item in file.deals {
            let model = Deal(
                id: item.id, kind: DealKind(rawValue: item.kindRaw) ?? .sale,
                status: DealStatus(rawValue: item.statusRaw) ?? .active, signedOn: item.signedOn,
                actualPriceCents: item.actualPriceCents, commissionReceivableCents: item.commissionReceivableCents,
                commissionReceivedCents: item.commissionReceivedCents, leaseStartOn: item.leaseStartOn,
                leaseEndOn: item.leaseEndOn, notes: item.notes
            )
            model.communityNameSnapshot = item.communityNameSnapshot
            model.propertyDescriptionSnapshot = item.propertyDescriptionSnapshot
            model.counterpartyNameSnapshot = item.counterpartyNameSnapshot
            model.voidReason = item.voidReason
            model.createdAt = item.createdAt
            model.updatedAt = item.updatedAt
            model.property = item.propertyID.flatMap { properties[$0] }
            model.contact = item.contactID.flatMap { contacts[$0] }
            model.clientNeed = item.clientNeedID.flatMap { needs[$0] }
            context.insert(model)
            deals[item.id] = model
        }
        for item in file.allocations {
            let model = DealCommissionAllocation(
                id: item.id, propertyFee: item.propertyFee, photoFee: item.photoFee,
                keyFee: item.keyFee, followUpPercent: item.followUpPercent
            )
            model.deal = deals[item.dealID]
            context.insert(model)
        }
        for item in file.tasks {
            let model = TaskItem(
                id: item.id, kind: TaskKind(rawValue: item.kindRaw) ?? .manual,
                state: TaskState(rawValue: item.stateRaw) ?? .open, title: item.title, notes: item.notes,
                dueAt: item.dueAt, completedAt: item.completedAt, sourceID: item.sourceID, sourceKey: item.sourceKey
            )
            model.createdAt = item.createdAt
            model.updatedAt = item.updatedAt
            context.insert(model)
        }
        if let workspace = file.workspace {
            context.insert(WorkspaceRecord(id: workspace.id, title: workspace.title, createdAt: workspace.createdAt))
        }
    }

    private static func wipe(_ context: ModelContext) throws {
        for item in try context.all(ViewingItem.self) { context.delete(item) }
        for item in try context.all(Viewing.self) { context.delete(item) }
        for item in try context.all(FollowUp.self) { context.delete(item) }
        for item in try context.all(DealCommissionAllocation.self) { context.delete(item) }
        for item in try context.all(Deal.self) { context.delete(item) }
        for item in try context.all(PropertyStatusEvent.self) { context.delete(item) }
        for item in try context.all(MediaAsset.self) { context.delete(item) }
        for item in try context.all(TaskItem.self) { context.delete(item) }
        for item in try context.all(ClientNeed.self) { context.delete(item) }
        for item in try context.all(Property.self) { context.delete(item) }
        for item in try context.all(Contact.self) { context.delete(item) }
        for item in try context.all(MarketComparable.self) { context.delete(item) }
        for item in try context.all(Community.self) { context.delete(item) }
        for item in try context.all(WorkspaceRecord.self) { context.delete(item) }
        try context.save()
    }

    private static func checkFile(_ url: URL, expectedSize: Int?, expectedHash: String, errors: inout [String]) throws -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else {
            errors.append("缺少文件 \(url.lastPathComponent)。")
            return 0
        }
        let size = Int64((try url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        if size > Int64(BusinessRules.maxMediaFileBytes) {
            errors.append("\(url.lastPathComponent) 超过 100 MB。")
        }
        if let expectedSize, Int64(expectedSize) != size {
            errors.append("\(url.lastPathComponent) 的大小和清单不一致。")
        }
        let digest = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        if !expectedHash.isEmpty && digest != expectedHash {
            errors.append("\(url.lastPathComponent) 的校验和不符。")
        }
        return expectedSize == nil ? 0 : size
    }

    private static func copyIntoPackage(_ packagePath: String, mediaDir: URL, sourceRelative: String) throws -> String {
        let source = MediaStore.fileURL(sourceRelative)
        let dest = mediaDir.appendingPathComponent(sourceRelative)
        if FileManager.default.fileExists(atPath: source.path) {
            try FileManager.default.copyItem(at: source, to: dest)
        } else {
            throw PortabilityError.invalid(["媒体文件缺失：\(sourceRelative)"])
        }
        let digest = SHA256.hash(data: try Data(contentsOf: dest)).map { String(format: "%02x", $0) }.joined()
        _ = packagePath
        return digest
    }

    private static func safetyDirectory() throws -> URL {
        let url = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("SafetyBackups", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func pruneSafetyBackups(in folder: URL, keeping: Int) {
        let urls = safetyBackups()
        for extra in urls.dropFirst(keeping) {
            try? FileManager.default.removeItem(at: extra)
        }
        _ = folder
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: Date())
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(formatter.string(from: date))
        }
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: text) { return date }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: text)
        }
        return decoder
    }

    private static func table(_ header: [String], _ rows: [[String]]) -> String {
        ([header] + rows).map { $0.map(cell).joined(separator: ",") }.joined(separator: "\n")
    }

    private static func cell(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private static func s(_ id: UUID) -> String { id.uuidString }
    private static func b(_ value: Bool) -> String { value ? "是" : "否" }
    private static func n(_ value: Double?) -> String { value.map { String($0) } ?? "" }
}

private extension Array where Element == String {
    func prepending(_ value: String) -> [String] { [value] + self }
}

struct BackupFile: Codable {
    var format: String
    var formatVersion: Int
    var appVersion: String
    var build: String
    var exportedAt: Date
    var encrypted: Bool
    var communities: [CommunityDTO]
    var contacts: [ContactDTO]
    var properties: [PropertyDTO]
    var media: [MediaDTO]
    var statusEvents: [StatusEventDTO]
    var clientNeeds: [ClientNeedDTO]
    var followUps: [FollowUpDTO]
    var viewings: [ViewingDTO]
    var viewingItems: [ViewingItemDTO]
    var deals: [DealDTO]
    var allocations: [AllocationDTO]
    var comparables: [ComparableDTO]
    var tasks: [TaskDTO]
    var workspace: WorkspaceDTO?
}

struct CommunityDTO: Codable {
    var id: UUID
    var name: String
    var aliases: [String]
    var district: String
    var address: String
    var latitude: Double?
    var longitude: Double?
    var notes: String
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    init(_ model: Community) {
        id = model.id; name = model.name; aliases = model.aliases; district = model.district
        address = model.address; latitude = model.latitude; longitude = model.longitude
        notes = model.notes; isArchived = model.isArchived; createdAt = model.createdAt; updatedAt = model.updatedAt
    }
}

struct ContactDTO: Codable {
    var id: UUID
    var displayName: String
    var phone: String
    var wechat: String
    var rolesRaw: String
    var notes: String
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    init(_ model: Contact) {
        id = model.id; displayName = model.displayName; phone = model.phone; wechat = model.wechat
        rolesRaw = model.rolesRaw; notes = model.notes; isArchived = model.isArchived
        createdAt = model.createdAt; updatedAt = model.updatedAt
    }
}

struct PropertyDTO: Codable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
    var communityID: UUID?
    var building: String
    var unit: String
    var room: String
    var listingKindRaw: String
    var statusRaw: String
    var askingPriceCents: Int
    var availableFrom: Date?
    var viewingMethod: String
    var bedrooms: Int
    var livingRooms: Int
    var bathrooms: Int
    var area: Double
    var floor: Int
    var totalFloors: Int
    var orientation: String
    var decoration: String
    var hasElevator: Bool
    var features: [String]
    var ownerID: UUID?
    var internalNotes: String
    var lastVerifiedAt: Date?
    var materialsVerifiedAt: Date?
    init(_ model: Property) {
        id = model.id; createdAt = model.createdAt; updatedAt = model.updatedAt; isArchived = model.isArchived
        communityID = model.community?.id; building = model.building; unit = model.unit; room = model.room
        listingKindRaw = model.listingKindRaw; statusRaw = model.statusRaw; askingPriceCents = model.askingPriceCents
        availableFrom = model.availableFrom; viewingMethod = model.viewingMethod; bedrooms = model.bedrooms
        livingRooms = model.livingRooms; bathrooms = model.bathrooms; area = model.area; floor = model.floor
        totalFloors = model.totalFloors; orientation = model.orientation; decoration = model.decoration
        hasElevator = model.hasElevator; features = model.features; ownerID = model.owner?.id
        internalNotes = model.internalNotes; lastVerifiedAt = model.lastVerifiedAt; materialsVerifiedAt = model.materialsVerifiedAt
    }
}

struct MediaDTO: Codable {
    var id: UUID
    var kindRaw: String
    var packagePath: String
    var thumbnailPackagePath: String
    var storedName: String
    var thumbnailStoredName: String
    var originalFilename: String
    var mimeType: String
    var fileSize: Int
    var sha256: String
    var thumbnailSha256: String
    var caption: String
    var sortOrder: Int
    var createdAt: Date
    var propertyID: UUID?
    var comparableID: UUID?
    init(_ model: MediaAsset) {
        id = model.id
        kindRaw = model.kindRaw
        storedName = model.relativePath
        thumbnailStoredName = model.thumbnailRelativePath
        packagePath = "media/\(model.relativePath)"
        thumbnailPackagePath = model.thumbnailRelativePath.isEmpty ? "" : "media/\(model.thumbnailRelativePath)"
        originalFilename = model.originalFilename
        mimeType = model.mimeType
        fileSize = model.fileSize
        sha256 = ""
        thumbnailSha256 = ""
        caption = model.caption
        sortOrder = model.sortOrder
        createdAt = model.createdAt
        propertyID = model.property?.id
        comparableID = model.comparable?.id
    }
}

struct StatusEventDTO: Codable {
    var id: UUID
    var occurredAt: Date
    var reason: String
    var relatedDealID: UUID?
    var fromRaw: String
    var toRaw: String
    var propertyID: UUID
    init(_ model: PropertyStatusEvent) {
        id = model.id; occurredAt = model.occurredAt; reason = model.reason; relatedDealID = model.relatedDealID
        fromRaw = model.fromRaw; toRaw = model.toRaw; propertyID = model.property?.id ?? UUID()
    }
}

struct ClientNeedDTO: Codable {
    var id: UUID
    var kindRaw: String
    var statusRaw: String
    var urgencyRaw: String
    var budgetMinCents: Int
    var budgetMaxCents: Int
    var preferredDistricts: [String]
    var preferredCommunityIDs: [UUID]
    var bedroomsMin: Int
    var bedroomsMax: Int
    var areaMin: Double
    var areaMax: Double
    var moveInDate: Date?
    var mustHaveFeatures: [String]
    var excludedFeatures: [String]
    var preferencesNote: String
    var source: String
    var closedReason: String
    var createdAt: Date
    var updatedAt: Date
    var contactID: UUID?
    init(_ model: ClientNeed) {
        id = model.id; kindRaw = model.kindRaw; statusRaw = model.statusRaw; urgencyRaw = model.urgencyRaw
        budgetMinCents = model.budgetMinCents; budgetMaxCents = model.budgetMaxCents
        preferredDistricts = model.preferredDistricts; preferredCommunityIDs = model.preferredCommunityIDs
        bedroomsMin = model.bedroomsMin; bedroomsMax = model.bedroomsMax; areaMin = model.areaMin; areaMax = model.areaMax
        moveInDate = model.moveInDate; mustHaveFeatures = model.mustHaveFeatures; excludedFeatures = model.excludedFeatures
        preferencesNote = model.preferencesNote; source = model.source; closedReason = model.closedReason
        createdAt = model.createdAt; updatedAt = model.updatedAt; contactID = model.contact?.id
    }
}

struct FollowUpDTO: Codable {
    var id: UUID
    var channelRaw: String
    var content: String
    var outcome: String
    var nextAction: String
    var nextDueAt: Date?
    var occurredAt: Date
    var createdAt: Date
    var updatedAt: Date
    var clientNeedID: UUID?
    var contactID: UUID?
    var propertyID: UUID?
    init(_ model: FollowUp) {
        id = model.id; channelRaw = model.channelRaw; content = model.content; outcome = model.outcome
        nextAction = model.nextAction; nextDueAt = model.nextDueAt; occurredAt = model.occurredAt
        createdAt = model.createdAt; updatedAt = model.updatedAt
        clientNeedID = model.clientNeed?.id; contactID = model.contact?.id; propertyID = model.property?.id
    }
}

struct ViewingDTO: Codable {
    var id: UUID
    var scheduledStart: Date
    var scheduledEnd: Date
    var meetingPoint: String
    var notes: String
    var statusRaw: String
    var createdAt: Date
    var updatedAt: Date
    var clientNeedID: UUID?
    init(_ model: Viewing) {
        id = model.id; scheduledStart = model.scheduledStart; scheduledEnd = model.scheduledEnd
        meetingPoint = model.meetingPoint; notes = model.notes; statusRaw = model.statusRaw
        createdAt = model.createdAt; updatedAt = model.updatedAt; clientNeedID = model.clientNeed?.id
    }
}

struct ViewingItemDTO: Codable {
    var id: UUID
    var sortOrder: Int
    var feedback: String
    var interestRaw: String
    var objections: String
    var viewingID: UUID
    var propertyID: UUID?
    init(_ model: ViewingItem) {
        id = model.id; sortOrder = model.sortOrder; feedback = model.feedback; interestRaw = model.interestRaw
        objections = model.objections; viewingID = model.viewing?.id ?? UUID(); propertyID = model.property?.id
    }
}

struct DealDTO: Codable {
    var id: UUID
    var kindRaw: String
    var statusRaw: String
    var signedOn: Date
    var actualPriceCents: Int
    var commissionReceivableCents: Int
    var commissionReceivedCents: Int
    var leaseStartOn: Date?
    var leaseEndOn: Date?
    var communityNameSnapshot: String
    var propertyDescriptionSnapshot: String
    var counterpartyNameSnapshot: String
    var notes: String
    var voidReason: String
    var createdAt: Date
    var updatedAt: Date
    var propertyID: UUID?
    var contactID: UUID?
    var clientNeedID: UUID?
    init(_ model: Deal) {
        id = model.id; kindRaw = model.kindRaw; statusRaw = model.statusRaw; signedOn = model.signedOn
        actualPriceCents = model.actualPriceCents; commissionReceivableCents = model.commissionReceivableCents
        commissionReceivedCents = model.commissionReceivedCents; leaseStartOn = model.leaseStartOn
        leaseEndOn = model.leaseEndOn; communityNameSnapshot = model.communityNameSnapshot
        propertyDescriptionSnapshot = model.propertyDescriptionSnapshot
        counterpartyNameSnapshot = model.counterpartyNameSnapshot; notes = model.notes; voidReason = model.voidReason
        createdAt = model.createdAt; updatedAt = model.updatedAt
        propertyID = model.property?.id; contactID = model.contact?.id; clientNeedID = model.clientNeed?.id
    }
}

struct AllocationDTO: Codable {
    var id: UUID
    var propertyFee: Bool
    var photoFee: Bool
    var keyFee: Bool
    var followUpPercent: Int
    var dealID: UUID
    init?(_ model: DealCommissionAllocation) {
        guard let dealID = model.deal?.id else { return nil }
        id = model.id; propertyFee = model.propertyFee; photoFee = model.photoFee
        keyFee = model.keyFee; followUpPercent = model.followUpPercent; self.dealID = dealID
    }
}

struct ComparableDTO: Codable {
    var id: UUID
    var kindRaw: String
    var dealDate: Date
    var priceCents: Int
    var area: Double
    var bedrooms: Int
    var decoration: String
    var floorDescription: String
    var sourceDescription: String
    var evidenceAssetID: UUID?
    var notes: String
    var createdAt: Date
    var updatedAt: Date
    var communityID: UUID?
    init(_ model: MarketComparable) {
        id = model.id; kindRaw = model.kindRaw; dealDate = model.dealDate; priceCents = model.priceCents
        area = model.area; bedrooms = model.bedrooms; decoration = model.decoration
        floorDescription = model.floorDescription; sourceDescription = model.sourceDescription
        evidenceAssetID = model.evidenceAssetID; notes = model.notes; createdAt = model.createdAt
        updatedAt = model.updatedAt; communityID = model.community?.id
    }
}

struct TaskDTO: Codable {
    var id: UUID
    var kindRaw: String
    var stateRaw: String
    var title: String
    var notes: String
    var dueAt: Date
    var completedAt: Date?
    var sourceID: UUID?
    var sourceKey: String
    var createdAt: Date
    var updatedAt: Date
    init(_ model: TaskItem) {
        id = model.id; kindRaw = model.kindRaw; stateRaw = model.stateRaw; title = model.title; notes = model.notes
        dueAt = model.dueAt; completedAt = model.completedAt; sourceID = model.sourceID; sourceKey = model.sourceKey
        createdAt = model.createdAt; updatedAt = model.updatedAt
    }
}

struct WorkspaceDTO: Codable {
    var id: UUID
    var title: String
    var createdAt: Date
}

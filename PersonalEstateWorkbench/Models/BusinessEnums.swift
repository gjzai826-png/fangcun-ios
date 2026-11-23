import Foundation

enum ListingKind: String, Codable, CaseIterable, Identifiable {
    case rent
    case sale

    var id: String { rawValue }

    var title: String {
        self == .rent ? "出租" : "出售"
    }

    var availableTitle: String {
        self == .rent ? "在租" : "在售"
    }

    var priceUnit: String {
        self == .rent ? "元/月" : "万元"
    }
}

enum PropertyStatus: String, Codable, CaseIterable, Identifiable {
    case available
    case reserved
    case rented
    case sold
    case offline
    case needsVerification
    case unknown

    var id: String { rawValue }

    func title(for kind: ListingKind) -> String {
        switch self {
        case .available: return kind.availableTitle
        case .reserved: return "已暂定"
        case .rented: return "已租"
        case .sold: return "已售"
        case .offline: return "已下架"
        case .needsVerification: return "待核实"
        case .unknown: return "无法识别"
        }
    }

    /// 在租、在售、已暂定算挂牌；其余进入「未挂牌」。
    var isListed: Bool {
        self == .available || self == .reserved
    }

    var needsReview: Bool {
        self == .needsVerification || self == .unknown
    }
}

enum PropertyBrowseTab: String, CaseIterable, Identifiable {
    case sale
    case rent
    case unlisted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sale: return "出售"
        case .rent: return "出租"
        case .unlisted: return "未挂牌"
        }
    }
}

enum PropertyBrowseSort: String, CaseIterable, Identifiable {
    case newest
    case priceAscending
    case priceDescending
    case areaDescending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest: return "最新"
        case .priceAscending: return "价格从低到高"
        case .priceDescending: return "价格从高到低"
        case .areaDescending: return "面积从大到小"
        }
    }
}

struct PropertyBrowseFilter: Equatable {
    var communityID: UUID?
    var district: String = ""
    var priceMin: Int?
    var priceMax: Int?
    var bedrooms: Int?
    var status: PropertyStatus?
    var includeArchived: Bool = false
    var recentOnly: Bool = false
    var photosOnly: Bool = false
    var elevatorOnly: Bool = false
    var building: String = ""
    var unit: String = ""
    var room: String = ""
    var sort: PropertyBrowseSort = .newest

    var isNarrowed: Bool {
        communityID != nil || !district.isEmpty || priceMin != nil || priceMax != nil
            || bedrooms != nil || status != nil || includeArchived || recentOnly
            || photosOnly || elevatorOnly || !building.isEmpty || !unit.isEmpty || !room.isEmpty
            || sort != .newest
    }
}

enum ContactRole: String, Codable, CaseIterable, Identifiable {
    case owner
    case tenant
    case buyer
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .owner: return "业主"
        case .tenant: return "租客"
        case .buyer: return "买家"
        case .other: return "其他"
        }
    }
}

enum MediaKind: String, Codable, CaseIterable, Identifiable {
    case photo
    case video

    var id: String { rawValue }
    var title: String { self == .photo ? "照片" : "视频" }
}

enum NeedKind: String, Codable, CaseIterable, Identifiable {
    case rent
    case buy
    case sale

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rent: return "求租"
        case .buy: return "求购"
        case .sale: return "出售"
        }
    }

    /// 求租看出租盘；求购和出售意向看在售盘。
    var matchingListing: ListingKind {
        self == .rent ? .rent : .sale
    }
}

enum NeedStatus: String, Codable, CaseIterable, Identifiable {
    case active
    case paused
    case closed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return "进行中"
        case .paused: return "已暂停"
        case .closed: return "已关闭"
        }
    }
}

enum Urgency: String, Codable, CaseIterable, Identifiable {
    case normal
    case soon
    case urgent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: return "一般"
        case .soon: return "尽快"
        case .urgent: return "紧急"
        }
    }
}

enum FollowUpChannel: String, Codable, CaseIterable, Identifiable {
    case call
    case wechat
    case inPerson

    var id: String { rawValue }

    var title: String {
        switch self {
        case .call: return "电话"
        case .wechat: return "微信"
        case .inPerson: return "面谈"
        }
    }
}

enum ViewingInterest: String, Codable, CaseIterable, Identifiable {
    case like
    case neutral
    case dislike

    var id: String { rawValue }

    var title: String {
        switch self {
        case .like: return "有意向"
        case .neutral: return "一般"
        case .dislike: return "不考虑"
        }
    }
}

/// 完整 case 未能从二进制成组恢复。界面动作是完成、取消、改期，因此用这三项。
enum ViewingStatus: String, Codable, CaseIterable, Identifiable {
    case scheduled
    case completed
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scheduled: return "待带看"
        case .completed: return "已完成"
        case .cancelled: return "已取消"
        }
    }
}

enum DealKind: String, Codable, CaseIterable, Identifiable {
    case sale
    case rent

    var id: String { rawValue }
    var title: String { self == .sale ? "买卖" : "租赁" }

    var listingKind: ListingKind {
        self == .sale ? .sale : .rent
    }
}

/// `voided` 能对上「已作废」。`ended` 对应「已退租」，是按界面动作补上的。
enum DealStatus: String, Codable, CaseIterable, Identifiable {
    case active
    case voided
    case ended

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return "有效"
        case .voided: return "已作废"
        case .ended: return "已退租"
        }
    }

    var countsTowardPerformance: Bool {
        self != .voided
    }
}

/// 按今日待办文案归类。完整 case 列表未能成组恢复。
enum TaskKind: String, Codable, CaseIterable, Identifiable {
    case verification
    case lease
    case viewing
    case followUp
    case manual

    var id: String { rawValue }

    var title: String {
        switch self {
        case .verification: return "房源核实"
        case .lease: return "租约到期"
        case .viewing: return "带看安排"
        case .followUp: return "客户跟进"
        case .manual: return "一般待办"
        }
    }
}

enum TaskState: String, Codable, CaseIterable, Identifiable {
    case open
    case completed
    case cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: return "待处理"
        case .completed: return "已完成"
        case .cancelled: return "已取消"
        }
    }
}

enum WorkspaceMode: String, CaseIterable, Identifiable {
    case formal
    case demo

    var id: String { rawValue }
    var title: String { self == .formal ? "正式工作台" : "演示数据" }
}

enum CSVExportKind: String, CaseIterable, Identifiable {
    case communities
    case contacts
    case properties
    case clientNeeds
    case followUps
    case viewings
    case deals
    case comparables
    case tasks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .communities: return "小区"
        case .contacts: return "联系人"
        case .properties: return "房源"
        case .clientNeeds: return "客户需求"
        case .followUps: return "跟进"
        case .viewings: return "带看"
        case .deals: return "成交"
        case .comparables: return "行情"
        case .tasks: return "待办"
        }
    }

    var filename: String { "方寸-\(title).csv" }
}

enum TodayQuickAction: String, CaseIterable, Identifiable {
    case registerDeal
    case writeFollowUp
    case addTask

    var id: String { rawValue }

    var title: String {
        switch self {
        case .registerDeal: return "登记成交"
        case .writeFollowUp: return "写跟进"
        case .addTask: return "添加待办"
        }
    }

    var systemImage: String {
        switch self {
        case .registerDeal: return "signature"
        case .writeFollowUp: return "text.bubble"
        case .addTask: return "checklist"
        }
    }
}

enum PropertyFeeOption: String, CaseIterable, Identifiable {
    case unspecified
    case included
    case excluded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unspecified: return "未填"
        case .included: return "包物业"
        case .excluded: return "不包物业"
        }
    }
}

enum ParkingOption: String, CaseIterable, Identifiable {
    case unspecified
    case included
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unspecified: return "未填"
        case .included: return "包车位"
        case .none: return "无车位"
        }
    }
}

enum OrientationOption: String, CaseIterable, Identifiable {
    case east = "东"
    case south = "南"
    case west = "西"
    case north = "北"
    case southeast = "东南"
    case southwest = "西南"
    case northeast = "东北"
    case northwest = "西北"
    case southNorth = "南北"
    case eastWest = "东西"

    var id: String { rawValue }
    var title: String { rawValue }
}

enum DecorationOption: String, CaseIterable, Identifiable {
    case rough = "毛坯"
    case simple = "简装"
    case refined = "精装"
    case luxury = "豪装"

    var id: String { rawValue }
    var title: String { rawValue }
}

enum FeatureToken {
    static let feeIncluded = "包物业"
    static let feeExcluded = "不包物业"
    static let parkingIncluded = "包车位"
    static let parkingNone = "无车位"
    static let elevator = "电梯"
    static let parking = "车位"

    static let feeTokens: Set<String> = [feeIncluded, feeExcluded]
    static let parkingTokens: Set<String> = [parkingIncluded, parkingNone]

    static func fee(in features: [String]) -> PropertyFeeOption {
        if features.contains(feeIncluded) { return .included }
        if features.contains(feeExcluded) { return .excluded }
        return .unspecified
    }

    static func parking(in features: [String]) -> ParkingOption {
        if features.contains(parkingIncluded) { return .included }
        if features.contains(parkingNone) { return .none }
        return .unspecified
    }

    static func replacing(features: [String], fee: PropertyFeeOption, parking: ParkingOption) -> [String] {
        var rest = features.filter { !feeTokens.contains($0) && !parkingTokens.contains($0) }
        switch fee {
        case .included: rest.append(feeIncluded)
        case .excluded: rest.append(feeExcluded)
        case .unspecified: break
        }
        switch parking {
        case .included: rest.append(parkingIncluded)
        case .none: rest.append(parkingNone)
        case .unspecified: break
        }
        return rest
    }
}

enum MatchBucket: String, CaseIterable, Identifiable {
    case qualified
    case needsVerification
    case previouslyRejected
    case excluded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qualified: return "满足硬条件"
        case .needsVerification: return "待核实候选"
        case .previouslyRejected: return "此前不考虑"
        case .excluded: return "因硬条件被排除"
        }
    }
}

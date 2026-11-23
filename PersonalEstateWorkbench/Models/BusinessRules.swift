import Foundation

enum BusinessRules {
    static let maxMediaFileBytes = 100 * 1024 * 1024
    static let maxMediaTotalBytes: Int64 = 16 * 1024 * 1024 * 1024
    static let leaseReminderDays = 30

    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func splitList(_ text: String) -> [String] {
        trimmed(text)
            .replacingOccurrences(of: "，", with: "、")
            .replacingOccurrences(of: ",", with: "、")
            .replacingOccurrences(of: " ", with: "、")
            .split(separator: "、")
            .map { trimmed(String($0)) }
            .filter { !$0.isEmpty }
    }

    static func digits(_ text: String) -> String {
        text.filter(\.isNumber)
    }

    static func validateCommunity(name: String) -> String? {
        trimmed(name).isEmpty ? "小区全名必填。" : nil
    }

    static func duplicateCommunityWarning(name: String, others: Int) -> String? {
        others > 0 ? "「\(trimmed(name))」可能重名。请结合区域和地址区分，系统不会自动合并。" : nil
    }

    static func duplicatePhoneWarning(phone: String, others: Int) -> String? {
        let number = digits(phone)
        guard number.count >= 6, others > 0 else { return nil }
        return "这个手机号可能重复。系统不会自动合并。"
    }

    static func validateContact(name: String, phone: String, wechat: String) -> String? {
        if trimmed(name).isEmpty {
            if !trimmed(phone).isEmpty || !trimmed(wechat).isEmpty {
                return "填写了联系方式时，需要同时写上称呼。"
            }
            return "至少写一个称呼。电话和微信可以后补。"
        }
        return nil
    }

    static func validateProperty(hasCommunity: Bool) -> String? {
        hasCommunity ? nil : "小区必填，其他内容可以后补。"
    }

    static func validateStatusChange(changed: Bool, reason: String) -> String? {
        if changed && trimmed(reason).isEmpty {
            return "改状态要填写状态变更原因。"
        }
        return nil
    }

    static func validateFollowUp(hasNeed: Bool, hasProperty: Bool, hasContact: Bool, contactMatchesNeed: Bool) -> String? {
        if !hasNeed && !hasProperty && !hasContact {
            return "跟进至少需要关联一条需求、房源或联系人。"
        }
        if hasNeed && hasContact && !contactMatchesNeed {
            return "跟进里的联系人需要和需求上的联系人一致。"
        }
        return nil
    }

    static func validateViewing(start: Date, end: Date, propertyCount: Int, hasDuplicate: Bool) -> String? {
        if end < start { return "结束时间不能早于开始时间。" }
        if propertyCount < 1 { return "一次带看至少选择一套当前可看的房源。" }
        if hasDuplicate { return "同一次带看不能重复同一套房源。" }
        return nil
    }

    static func propertyIsViewable(_ property: Property, for need: NeedKind) -> Bool {
        !property.isArchived && property.status.isListed && property.listingKind == need.matchingListing
    }

    static func validateDeal(
        kind: DealKind,
        property: Property?,
        priceCents: Int,
        leaseStart: Date?,
        leaseEnd: Date?,
        otherLeaseRanges: [(Date, Date)]
    ) -> String? {
        guard let property else { return "要先选定房源。" }
        if property.listingKind != kind.listingKind {
            return "成交类型必须和房源的租售类型一致。"
        }
        if priceCents <= 0 { return "成交价要大于 0。" }
        if kind == .rent {
            guard let leaseStart, let leaseEnd else { return "租赁必须填写有效租期。" }
            if leaseEnd < leaseStart { return "租约结束不能早于开始。" }
            for range in otherLeaseRanges {
                let overlaps = leaseStart < range.1 && range.0 < leaseEnd
                if overlaps { return "租期不能和这套房已有的有效租约重叠。" }
            }
        }
        return nil
    }

    static func validateComparable(priceCents: Int, source: String, hasDate: Bool) -> String? {
        if !hasDate { return "行情日期要有效。" }
        if priceCents <= 0 { return "行情价格必须大于 0。" }
        if trimmed(source).isEmpty { return "行情必须填写来源。" }
        return nil
    }

    static func validateBackupFile(size: Int64) -> String? {
        if size > Int64(maxMediaFileBytes) { return "单个媒体文件不能超过 100 MB。" }
        return nil
    }
}

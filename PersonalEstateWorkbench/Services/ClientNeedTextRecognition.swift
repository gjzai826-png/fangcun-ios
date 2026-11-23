import Foundation

struct RecognizedNeed: Identifiable, Hashable {
    var id = UUID()
    var sourceText: String
    var kind: NeedKind?
    var kindNeedsConfirm: Bool = false
    var budgetMinCents: Int?
    var budgetMaxCents: Int?
    var budgetNeedsConfirm: Bool = false
    var bedroomsMin: Int?
    var bedroomsMax: Int?
    var areaMin: Double?
    var areaMax: Double?
    var districts: [String] = []
    var communityIDs: [UUID] = []
    var communityNeedsConfirm: Bool = false
    var mustHave: [String] = []
    var excluded: [String] = []
    var featureNeedsConfirm: Bool = false
    var warnings: [String] = []
}

enum ClientNeedTextRecognition {
    static func recognize(_ text: String, communities: [Community]) -> RecognizedNeed {
        var result = RecognizedNeed(sourceText: text)
        let body = text.replacingOccurrences(of: "\n", with: " ")
        recognizeKind(body, into: &result)
        recognizeBudget(body, into: &result)
        recognizeRooms(body, into: &result)
        recognizeArea(body, into: &result)
        recognizeFeatures(body, into: &result)
        recognizePlaces(body, communities: communities, into: &result)
        if result.warnings.isEmpty && result.kind == nil && result.budgetMaxCents == nil && result.bedroomsMin == nil {
            result.warnings.append("没有识别出可以自动填写的条件，请手动填写。")
        }
        return result
    }

    private static func recognizeKind(_ text: String, into result: inout RecognizedNeed) {
        let rent = TextScan.contains("求租|租房|想租|要租|出租需求", in: text)
        let buy = TextScan.contains("求购|买房|购房|想买|要买", in: text)
        let sale = TextScan.contains("出售|卖房|想卖", in: text)
        let bothMarkets = TextScan.contains("租售都|又租又买|租和买|可租可买", in: text)
        if bothMarkets || (rent && (buy || sale)) {
            result.kindNeedsConfirm = true
            result.warnings.append("同时提到了租和买，类型需要手动确认。")
            return
        }
        if rent { result.kind = .rent }
        else if buy { result.kind = .buy }
        else if sale { result.kind = .sale }
    }

    private static func recognizeBudget(_ text: String, into result: inout RecognizedNeed) {
        if TextScan.contains("左右|大约|差不多", in: text) && TextScan.contains("预算|万|元", in: text) {
            let fuzzy = TextScan.contains(#"\d+(?:\.\d+)?\s*(?:万|元)?\s*(?:左右|大约)"#, in: text)
            if fuzzy {
                result.budgetNeedsConfirm = true
                result.warnings.append("预算带有「左右」，不自动填写。")
                return
            }
        }
        let hasWan = TextScan.contains(#"\d+(?:\.\d+)?\s*万"#, in: text)
        let hasYuan = TextScan.contains(#"\d+(?:\.\d+)?\s*元"#, in: text)
        if hasWan && hasYuan {
            result.budgetNeedsConfirm = true
            result.warnings.append("预算同时出现了「万」和「元」，请手动确认。")
            return
        }
        if let pair = TextScan.groups(#"(\d+(?:\.\d+)?)\s*[-~到至]\s*(\d+(?:\.\d+)?)\s*(万|元)?"#, in: text).first {
            let unit = pair.count > 3 ? pair[3] : ""
            result.budgetMinCents = cents(pair[1], unit: unit, kind: result.kind, hasWan: hasWan)
            result.budgetMaxCents = cents(pair[2], unit: unit, kind: result.kind, hasWan: hasWan)
            return
        }
        if let cap = TextScan.groups(#"(?:不超过|以内|以下|最高)\s*(\d+(?:\.\d+)?)\s*(万|元)?"#, in: text).first {
            result.budgetMaxCents = cents(cap[1], unit: cap.count > 2 ? cap[2] : "", kind: result.kind, hasWan: hasWan)
            return
        }
        if let single = TextScan.groups(#"(?:预算|总价|月租|租金)\s*(\d+(?:\.\d+)?)\s*(万|元)?"#, in: text).first {
            let value = cents(single[1], unit: single.count > 2 ? single[2] : "", kind: result.kind, hasWan: hasWan)
            result.budgetMaxCents = value
            return
        }
        if let wan = TextScan.groups(#"(\d+(?:\.\d+)?)\s*万"#, in: text).first {
            result.budgetMaxCents = Money.cents(fromWan: Double(wan[1]) ?? 0)
        }
    }

    private static func cents(_ raw: String, unit: String, kind: NeedKind?, hasWan: Bool) -> Int {
        let value = Double(raw) ?? 0
        let asWan: Bool
        if unit == "元" || kind == .rent {
            asWan = unit == "万"
        } else if unit == "万" || hasWan {
            asWan = true
        } else if kind == .buy || kind == .sale {
            asWan = true
        } else {
            // 类型和单位都不清楚时，小于 1000 按「万」，否则按元。
            asWan = value > 0 && value < 1000
        }
        return asWan ? Money.cents(fromWan: value) : Money.cents(fromYuan: value)
    }

    private static func recognizeRooms(_ text: String, into result: inout RecognizedNeed) {
        if let pair = TextScan.groups(#"([0-9一二两三四五])\s*[-到至]\s*([0-9一二两三四五])\s*室"#, in: text).first,
           let lower = TextScan.chineseNumber(pair[1]),
           let upper = TextScan.chineseNumber(pair[2]) {
            result.bedroomsMin = min(lower, upper)
            result.bedroomsMax = max(lower, upper)
            return
        }
        if let one = TextScan.groups(#"([0-9一二两三四五])\s*室"#, in: text).first,
           let value = TextScan.chineseNumber(one[1]) {
            result.bedroomsMin = value
            result.bedroomsMax = value
        }
    }

    private static func recognizeArea(_ text: String, into result: inout RecognizedNeed) {
        if let pair = TextScan.groups(#"(\d+(?:\.\d+)?)\s*[-到至]\s*(\d+(?:\.\d+)?)\s*(?:㎡|平米|平方|平)"#, in: text).first {
            result.areaMin = Double(pair[1])
            result.areaMax = Double(pair[2])
            return
        }
        if let one = TextScan.groups(#"(\d+(?:\.\d+)?)\s*(?:㎡|平米|平方)"#, in: text).first {
            result.areaMin = Double(one[1])
            result.areaMax = Double(one[1])
        }
    }

    private static func recognizeFeatures(_ text: String, into result: inout RecognizedNeed) {
        let wantElevator = TextScan.contains("要电梯|必须有电梯|必须电梯|带电梯|有电梯", in: text)
        let noElevator = TextScan.contains("不要电梯|不需要电梯|无电梯|没有电梯", in: text)
        if wantElevator && noElevator {
            result.featureNeedsConfirm = true
            result.warnings.append("电梯要求互相冲突，没有自动填写。")
        } else if wantElevator {
            result.mustHave.append(FeatureToken.elevator)
        } else if noElevator {
            result.excluded.append(FeatureToken.elevator)
        }

        let wantParking = TextScan.contains("要车位|必须有车位|带车位|有车位", in: text)
        let noParking = TextScan.contains("不要车位|不需要车位|无车位|没有车位", in: text)
        if wantParking && noParking {
            result.featureNeedsConfirm = true
            result.warnings.append("车位要求互相冲突，没有自动填写。")
        } else if wantParking {
            result.mustHave.append(FeatureToken.parking)
        } else if noParking {
            result.excluded.append(FeatureToken.parking)
        }
    }

    private static func recognizePlaces(_ text: String, communities: [Community], into result: inout RecognizedNeed) {
        var hits: [(Community, Int)] = []
        for community in communities where !community.isArchived {
            let names = [community.name] + community.aliases
            let longest = names.map { $0.count }.max() ?? 0
            if names.contains(where: { !$0.isEmpty && text.contains($0) }) {
                hits.append((community, longest))
            }
        }
        let longest = hits.map(\.1).max() ?? 0
        let kept = hits.filter { $0.1 == longest || !hits.contains { other in
            other.0.id != $0.0.id && other.1 > $0.1 && text.contains(other.0.name)
        } }
        let unique = Dictionary(grouping: kept, by: { $0.0.id }).compactMap { $0.value.first?.0 }
        if unique.count == 1 {
            result.communityIDs = [unique[0].id]
        } else if unique.count > 1 {
            result.communityNeedsConfirm = true
            result.warnings.append("匹配到多个小区，请手动选择。")
        }
        var districts = Set(unique.map(\.district).filter { !$0.isEmpty && text.contains($0) })
        for match in TextScan.groups(#"([\u{4e00}-\u{9fa5}]{2,6}区)"#, in: text) {
            districts.insert(match[1])
        }
        result.districts = districts.sorted()
    }
}

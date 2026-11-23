import Foundation

enum Money {
    /// 1 万 = 1_000_000 分。
    static func cents(fromWan wan: Double) -> Int {
        Int((wan * 1_000_000).rounded())
    }

    static func cents(fromYuan yuan: Double) -> Int {
        Int((yuan * 100).rounded())
    }

    static func wan(fromCents cents: Int) -> Double {
        Double(cents) / 1_000_000
    }

    static func yuan(fromCents cents: Int) -> Double {
        Double(cents) / 100
    }

    static func yuanText(_ cents: Int) -> String {
        let yuan = Double(cents) / 100
        return yuan.formatted(.number.precision(.fractionLength(0...2)).grouping(.automatic))
    }

    static func saleText(_ cents: Int) -> String {
        guard cents > 0 else { return "未报价" }
        let wan = Double(cents) / 1_000_000
        if wan >= 1 {
            let text = wan.formatted(.number.precision(.fractionLength(0...2)))
            return "\(text)万"
        }
        return yuanText(cents) + "元"
    }

    static func rentText(_ cents: Int) -> String {
        guard cents > 0 else { return "未报价" }
        return yuanText(cents) + "元/月"
    }

    static func priceText(_ cents: Int, kind: ListingKind) -> String {
        kind == .sale ? saleText(cents) : rentText(cents)
    }

    static func parse(_ text: String, kind: ListingKind) -> Int? {
        let cleaned = text
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "，", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let value = Double(cleaned) else { return nil }
        return kind == .sale ? cents(fromWan: value) : cents(fromYuan: value)
    }
}

enum CNDate {
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func friendly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: date)
    }

    static func shortDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func dayTime(_ date: Date) -> String {
        "\(shortDay(date)) \(time(date))"
    }

    static func sameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        Calendar.current.isDate(lhs, inSameDayAs: rhs)
    }

    static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }
}

enum TextScan {
    static func groups(_ pattern: String, in text: String) -> [[String]] {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, options: [], range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                let part = match.range(at: index)
                guard part.location != NSNotFound, let swiftRange = Range(part, in: text) else { return "" }
                return String(text[swiftRange])
            }
        }
    }

    static func contains(_ pattern: String, in text: String) -> Bool {
        !groups(pattern, in: text).isEmpty
    }

    static func chineseNumber(_ token: String) -> Int? {
        if let value = Int(token) { return value }
        let map: [Character: Int] = ["零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        if token.count == 1, let value = map[token.first!] { return value }
        return nil
    }
}

enum StarStore {
    private static let starKey = "starred.community.ids"
    private static let historyKey = "property.search.history"

    static var starredCommunityIDs: [UUID] {
        get {
            (UserDefaults.standard.stringArray(forKey: starKey) ?? []).compactMap(UUID.init(uuidString:))
        }
        set {
            UserDefaults.standard.set(newValue.map(\.uuidString), forKey: starKey)
        }
    }

    static func isStarred(_ id: UUID) -> Bool {
        starredCommunityIDs.contains(id)
    }

    static func toggleStar(_ id: UUID) {
        var ids = starredCommunityIDs
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
        } else {
            ids.insert(id, at: 0)
        }
        starredCommunityIDs = ids
    }

    static var searchHistory: [String] {
        get { UserDefaults.standard.stringArray(forKey: historyKey) ?? [] }
        set { UserDefaults.standard.set(Array(newValue.prefix(8)), forKey: historyKey) }
    }

    static func rememberSearch(_ text: String) {
        let trimmed = BusinessRules.trimmed(text)
        guard !trimmed.isEmpty else { return }
        var items = searchHistory.filter { $0 != trimmed }
        items.insert(trimmed, at: 0)
        searchHistory = items
    }
}

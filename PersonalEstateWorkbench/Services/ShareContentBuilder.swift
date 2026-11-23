import Foundation

enum ShareContentBuilder {
    static func recommendation(for property: Property) -> String {
        var lines: [String] = []
        lines.append("【\(property.communityName)】\(property.listingKind.title)")
        var facts = [property.layoutText, property.areaText]
        if !property.orientation.isEmpty { facts.append(property.orientation) }
        if !property.decoration.isEmpty { facts.append(property.decoration) }
        if property.hasElevator { facts.append("有电梯") }
        if !property.floorText.isEmpty { facts.append(property.floorText) }
        lines.append(facts.joined(separator: " · "))
        lines.append("报价 \(Money.priceText(property.askingPriceCents, kind: property.listingKind))")
        let tags = property.features.filter { !$0.isEmpty }
        if !tags.isEmpty { lines.append(tags.joined(separator: "、")) }
        if let date = property.availableFrom {
            lines.append("可入住 \(CNDate.day(date))")
        }
        if !property.viewingMethod.isEmpty {
            lines.append("看房：\(property.viewingMethod)")
        }
        var place: [String] = []
        if let district = property.community?.district, !district.isEmpty { place.append(district) }
        if let address = property.community?.address, !address.isEmpty { place.append(address) }
        if !place.isEmpty { lines.append(place.joined(separator: " · ")) }
        return lines.joined(separator: "\n")
    }

    static func videoBaseName(for property: Property) -> String {
        var parts = [property.communityName]
        if property.askingPriceCents > 0 {
            parts.append(Money.priceText(property.askingPriceCents, kind: property.listingKind))
        }
        if let fee = property.features.first(where: { FeatureToken.feeTokens.contains($0) }) {
            parts.append(fee)
        }
        if let parking = property.features.first(where: { FeatureToken.parkingTokens.contains($0) }) {
            parts.append(parking)
        }
        let joined = parts.joined(separator: "-")
        let cleaned = joined.unicodeScalars.map { scalar -> Character in
            let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            return forbidden.contains(scalar) ? "-" : Character(scalar)
        }
        let name = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "房源视频" : name
    }
}

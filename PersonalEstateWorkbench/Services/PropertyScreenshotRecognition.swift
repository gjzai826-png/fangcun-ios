import UIKit
import Vision

struct RecognizedProperty: Identifiable, Hashable {
    var id = UUID()
    var sourceText: String = ""
    var communityID: UUID?
    var suggestedCommunityName: String = ""
    var candidateCommunityIDs: [UUID] = []
    var listingKind: ListingKind?
    var askingPriceCents: Int?
    var bedrooms: Int?
    var livingRooms: Int?
    var bathrooms: Int?
    var area: Double?
    var floor: Int?
    var totalFloors: Int?
    var orientation: String?
    var decoration: String?
    var hasElevator: Bool?
    var warnings: [String] = []
}

private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resume(_ continuation: CheckedContinuation<[String], Never>, with value: [String]) {
        lock.lock()
        let shouldResume = !resumed
        resumed = true
        lock.unlock()
        if shouldResume {
            continuation.resume(returning: value)
        }
    }
}

enum PropertyScreenshotRecognition {
    static func recognize(_ image: UIImage, communities: [Community]) async -> RecognizedProperty {
        let lines = await readLines(from: image)
        return parse(lines.joined(separator: "\n"), communities: communities)
    }

    static func parse(_ text: String, communities: [Community]) -> RecognizedProperty {
        var result = RecognizedProperty(sourceText: text)
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        if TextScan.contains(#"1[3-9]\d{9}"#, in: flat) {
            result.warnings.append("截图里像是有电话，没有写入。业主电话请手填。")
        }
        if TextScan.contains("车位|物业", in: flat) {
            result.warnings.append("车位和物业费不从截图自动填写，请手填。")
        }
        recognizePrice(flat, into: &result)
        recognizeLayout(flat, into: &result)
        recognizeArea(flat, into: &result)
        recognizeFloor(flat, into: &result)
        recognizeOrientation(flat, into: &result)
        recognizeDecoration(flat, into: &result)
        recognizeElevator(flat, into: &result)
        recognizeCommunity(text, communities: communities, into: &result)
        if result.askingPriceCents == nil && result.bedrooms == nil && result.communityID == nil && result.suggestedCommunityName.isEmpty {
            result.warnings.append("没有识别出小区或报价，请对照截图手填。")
        }
        return result
    }

    private static func recognizePrice(_ text: String, into result: inout RecognizedProperty) {
        let wan = TextScan.groups(#"(\d+(?:\.\d+)?)\s*万"#, in: text)
        let monthly = TextScan.groups(#"(\d+(?:\.\d+)?)\s*元\s*/?\s*月"#, in: text)
        if !wan.isEmpty && !monthly.isEmpty {
            result.warnings.append("报价同时出现总价和月租，请手填。")
            return
        }
        if let value = wan.first, let number = Double(value[1]) {
            result.listingKind = .sale
            result.askingPriceCents = Money.cents(fromWan: number)
            return
        }
        if let value = monthly.first, let number = Double(value[1]) {
            result.listingKind = .rent
            result.askingPriceCents = Money.cents(fromYuan: number)
        }
    }

    private static func recognizeLayout(_ text: String, into result: inout RecognizedProperty) {
        guard let match = TextScan.groups(#"(\d+)\s*室\s*(\d+)\s*厅(?:\s*(\d+)\s*卫)?"#, in: text).first else { return }
        result.bedrooms = Int(match[1])
        result.livingRooms = Int(match[2])
        if match.count > 3, let baths = Int(match[3]) { result.bathrooms = baths }
    }

    private static func recognizeArea(_ text: String, into result: inout RecognizedProperty) {
        guard let match = TextScan.groups(#"(\d+(?:\.\d+)?)\s*(?:㎡|m²|平米|平方)"#, in: text).first else { return }
        result.area = Double(match[1])
    }

    private static func recognizeFloor(_ text: String, into result: inout RecognizedProperty) {
        if let match = TextScan.groups(#"(\d{1,3})\s*/\s*(\d{1,3})\s*层?"#, in: text).first {
            result.floor = Int(match[1])
            result.totalFloors = Int(match[2])
            return
        }
        if let match = TextScan.groups(#"(\d{1,3})\s*层"#, in: text).first {
            result.floor = Int(match[1])
        }
    }

    private static func recognizeOrientation(_ text: String, into result: inout RecognizedProperty) {
        let ordered = ["南北", "东西", "东南", "东北", "西南", "西北", "朝南", "朝北", "朝东", "朝西", "南", "北", "东", "西"]
        for token in ordered where text.contains(token) {
            result.orientation = token.replacingOccurrences(of: "朝", with: "")
            return
        }
    }

    private static func recognizeDecoration(_ text: String, into result: inout RecognizedProperty) {
        for option in DecorationOption.allCases where text.contains(option.rawValue) {
            result.decoration = option.rawValue
            return
        }
    }

    private static func recognizeElevator(_ text: String, into result: inout RecognizedProperty) {
        let yes = TextScan.contains("有电梯|带电梯|电梯房", in: text)
        let no = TextScan.contains("无电梯|没有电梯", in: text)
        if yes && no {
            result.warnings.append("电梯信息互相冲突，请手填。")
        } else if yes {
            result.hasElevator = true
        } else if no {
            result.hasElevator = false
        }
    }

    private static func recognizeCommunity(_ text: String, communities: [Community], into result: inout RecognizedProperty) {
        let lines = text.split(whereSeparator: \.isNewline).map { BusinessRules.trimmed(String($0)) }
        var hits: [Community] = []
        for community in communities where !community.isArchived {
            let names = ([community.name] + community.aliases).filter { $0.count >= 2 }
            if names.contains(where: { text.contains($0) }) {
                hits.append(community)
            }
        }
        let longest = hits.map(\.name.count).max() ?? 0
        let narrowed = hits.filter { community in
            !hits.contains { other in other.id != community.id && other.name.count > community.name.count && other.name.contains(community.name) }
        }
        if narrowed.count == 1 {
            result.communityID = narrowed[0].id
        } else if narrowed.count > 1 {
            result.candidateCommunityIDs = narrowed.map(\.id)
            result.warnings.append("小区没有唯一匹配，请手选或新建。")
        } else if longest == 0 {
            let suffixes = ["花园", "公寓", "府", "苑", "城", "湾", "庭", "公馆", "小区", "国际"]
            if let line = lines.first(where: { line in
                line.count <= 16 && suffixes.contains(where: { line.contains($0) })
            }) {
                result.suggestedCommunityName = line
                result.warnings.append("没有对上已有小区，可以按「\(line)」新建，或手选。")
            }
        }
    }

    private static func readLines(from image: UIImage) async -> [String] {
        guard let cgImage = normalized(image) else { return [] }
        return await withCheckedContinuation { continuation in
            let gate = ResumeGate()
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                gate.resume(continuation, with: lines)
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                gate.resume(continuation, with: [])
            }
        }
    }

    private static func normalized(_ image: UIImage) -> CGImage? {
        let maxSide: CGFloat = 2000
        var size = image.size
        let longest = max(size.width, size.height)
        if longest > maxSide {
            let scale = maxSide / longest
            size = CGSize(width: size.width * scale, height: size.height * scale)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }
}

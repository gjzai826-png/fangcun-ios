import SwiftData
import SwiftUI

struct PropertyScreenshotReview: View {
    var recognized: RecognizedProperty
    var onConfirm: (RecognizedProperty) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Community.name) private var communities: [Community]
    @State private var draft: RecognizedProperty
    @State private var showCreate = false

    init(recognized: RecognizedProperty, onConfirm: @escaping (RecognizedProperty) -> Void) {
        self.recognized = recognized
        self.onConfirm = onConfirm
        _draft = State(initialValue: recognized)
    }

    var body: some View {
        Form {
            Section("识别结果") {
                Text("截图不会进入房源相册。业主电话、车位和物业费请在表单里手填。")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                if draft.warnings.isEmpty {
                    Text("下面这些字段会填进新建表单，保存前还能改。")
                        .font(.footnote)
                } else {
                    ForEach(draft.warnings, id: \.self) { warning in
                        Text(warning).foregroundStyle(Theme.warn)
                    }
                }
            }
            Section("小区") {
                Picker("小区", selection: $draft.communityID) {
                    Text("手选或新建").tag(UUID?.none)
                    ForEach(communities) { community in
                        Text(community.name).tag(Optional(community.id))
                    }
                }
                if !draft.suggestedCommunityName.isEmpty && draft.communityID == nil {
                    Button("按「\(draft.suggestedCommunityName)」新建") { showCreate = true }
                }
            }
            Section("已识别") {
                LabeledContent("租售", value: draft.listingKind?.title ?? "未识别")
                LabeledContent("报价", value: priceText)
                LabeledContent("户型", value: layoutText)
                LabeledContent("面积", value: draft.area.map { "\($0)㎡" } ?? "未识别")
                LabeledContent("楼层", value: floorText)
                LabeledContent("朝向", value: draft.orientation ?? "未识别")
                LabeledContent("装修", value: draft.decoration ?? "未识别")
                LabeledContent("电梯", value: draft.hasElevator.map { $0 ? "有" : "无" } ?? "未识别")
            }
            if !draft.sourceText.isEmpty {
                Section("识别原文") {
                    Text(draft.sourceText).font(.footnote).foregroundStyle(Theme.muted)
                }
            }
        }
        .navigationTitle("核对截图")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("填入表单") { onConfirm(draft) } }
        }
        .sheet(isPresented: $showCreate) {
            NavigationStack {
                CommunityFormView(suggestedName: draft.suggestedCommunityName) { id in
                    draft.communityID = id
                }
            }
        }
    }

    private var priceText: String {
        guard let cents = draft.askingPriceCents, let kind = draft.listingKind else { return "未识别" }
        return Money.priceText(cents, kind: kind)
    }

    private var layoutText: String {
        guard draft.bedrooms != nil || draft.livingRooms != nil else { return "未识别" }
        return "\(draft.bedrooms ?? 0)室\(draft.livingRooms ?? 0)厅\(draft.bathrooms ?? 0)卫"
    }

    private var floorText: String {
        switch (draft.floor, draft.totalFloors) {
        case let (floor?, total?): return "\(floor)/\(total)层"
        case let (floor?, nil): return "\(floor)层"
        default: return "未识别"
        }
    }
}

import SwiftData
import SwiftUI

struct ClientNeedListView: View {
    @Query(sort: \ClientNeed.updatedAt, order: .reverse) private var needs: [ClientNeed]
    @State private var statusFilter: NeedStatus? = .active
    @State private var creating = false
    @State private var path = NavigationPath()

    private var visible: [ClientNeed] {
        needs.filter { statusFilter == nil || $0.status == statusFilter }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List(visible) { need in
                NavigationLink(value: RecordRoute.need(need.id)) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(need.contact?.displayName ?? "未关联联系人").font(.body.weight(.semibold))
                            Spacer()
                            Badge(text: need.urgency.title, color: need.urgency == .urgent ? Theme.bad : Theme.accent)
                        }
                        Text("\(need.kind.title) · \(need.status.title) · \(need.budgetText)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                        if !need.preferredDistricts.isEmpty {
                            Text(need.preferredDistricts.joined(separator: "、"))
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            .navigationTitle("客户")
            .navigationDestination(for: RecordRoute.self) { RouteDestination(route: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("状态", selection: $statusFilter) {
                        Text("全部").tag(NeedStatus?.none)
                        ForEach(NeedStatus.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("新增") { creating = true } }
            }
            .sheet(isPresented: $creating) { NavigationStack { ClientNeedFormView() } }
            .overlay {
                if visible.isEmpty {
                    EmptyStateView(title: "还没有客户需求", message: "可以粘贴一段找房文字，核对后再写入。", systemImage: "person.2")
                }
            }
        }
    }
}

struct ClientNeedDetailView: View {
    var needID: UUID
    @Query private var needs: [ClientNeed]
    @Environment(\.modelContext) private var context
    @State private var editing = false
    @State private var follow = false
    @State private var viewing = false
    @State private var closing = false
    @State private var closeReason = ""
    @State private var confirmClosedViewing = false
    private var need: ClientNeed? { needs.first { $0.id == needID } }

    var body: some View {
        Group {
            if let need {
                List {
                    Section {
                        InfoRow(title: "联系人", value: need.contact?.displayName ?? "")
                        InfoRow(title: "类型", value: need.kind.title)
                        InfoRow(title: "状态", value: need.status.title)
                        InfoRow(title: "紧急", value: need.urgency.title)
                        InfoRow(title: "预算", value: need.budgetText)
                        InfoRow(title: "区域", value: need.preferredDistricts.joined(separator: "、"))
                        InfoRow(title: "户型", value: roomText(need))
                        InfoRow(title: "面积", value: areaText(need))
                        InfoRow(title: "必须", value: need.mustHaveFeatures.joined(separator: "、"))
                        InfoRow(title: "排除", value: need.excludedFeatures.joined(separator: "、"))
                        InfoRow(title: "来源", value: need.source)
                        if let date = need.moveInDate { InfoRow(title: "入住", value: CNDate.day(date)) }
                        if !need.preferencesNote.isEmpty { Text(need.preferencesNote) }
                        if need.status == .closed { InfoRow(title: "关闭原因", value: need.closedReason) }
                    }
                    Section {
                        NavigationLink("匹配房源", value: RecordRoute.matchNeed(need.id))
                        Button("写跟进") { follow = true }
                        Button("安排带看") {
                            if need.status == .closed { confirmClosedViewing = true } else { viewing = true }
                        }
                        if need.status != .closed { Button("关闭需求") { closing = true } }
                    }
                    Section("跟进") {
                        ForEach(need.followUps.sorted { $0.occurredAt > $1.occurredAt }) { item in
                            VStack(alignment: .leading) {
                                Text("\(item.channel.title) · \(CNDate.dayTime(item.occurredAt))").font(.caption).foregroundStyle(Theme.muted)
                                Text(item.content)
                            }
                        }
                    }
                    Section("带看") {
                        ForEach(need.viewings.sorted { $0.scheduledStart > $1.scheduledStart }) { item in
                            NavigationLink(value: RecordRoute.viewing(item.id)) {
                                Text("\(CNDate.dayTime(item.scheduledStart)) · \(item.status.title)")
                            }
                        }
                    }
                }
                .navigationTitle(need.contact?.displayName ?? "需求")
                .toolbar { Button("编辑") { editing = true } }
                .sheet(isPresented: $editing) { NavigationStack { ClientNeedFormView(existingID: need.id, contactID: need.contact?.id) } }
                .sheet(isPresented: $follow) { NavigationStack { FollowUpFormView(needID: need.id, contactID: need.contact?.id) } }
                .sheet(isPresented: $viewing) { NavigationStack { ViewingFormView(needID: need.id) } }
                .alert("关闭原因", isPresented: $closing) {
                    TextField("原因", text: $closeReason)
                    Button("关闭需求") {
                        guard !BusinessRules.trimmed(closeReason).isEmpty else { return }
                        need.status = .closed
                        need.closedReason = BusinessRules.trimmed(closeReason)
                        need.updatedAt = Date()
                        try? context.save()
                    }
                    Button("取消", role: .cancel) {}
                } message: { Text("关闭后仍保留历史关系。") }
                .confirmationDialog("该需求已关闭，仍要安排带看？", isPresented: $confirmClosedViewing, titleVisibility: .visible) {
                    Button("仍然安排") { viewing = true }
                    Button("取消", role: .cancel) {}
                }
            } else {
                EmptyStateView(title: "没有这条需求", message: "", systemImage: "person")
            }
        }
    }

    private func roomText(_ need: ClientNeed) -> String {
        if need.bedroomsMin == 0 && need.bedroomsMax == 0 { return "" }
        if need.bedroomsMin == need.bedroomsMax { return "\(need.bedroomsMin)室" }
        return "\(need.bedroomsMin)–\(need.bedroomsMax)室"
    }

    private func areaText(_ need: ClientNeed) -> String {
        if need.areaMin == 0 && need.areaMax == 0 { return "" }
        return "\(need.areaMin)–\(need.areaMax)㎡"
    }
}

struct ClientNeedFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var contacts: [Contact]
    @Query private var communities: [Community]
    @Query private var needs: [ClientNeed]
    var existingID: UUID?
    var contactID: UUID?

    @State private var draft = NeedDraft()
    @State private var isDirty = false
    @State private var didLoad = false
    @State private var errorMessage: String?
    @State private var showPaste = false
    @State private var pasteText = ""
    @State private var recognized: RecognizedNeed?
    @State private var showContact = false

    var body: some View {
        Form {
            Section {
                Picker("联系人", selection: field(\.contactID)) {
                    Text("请选择").tag(UUID?.none)
                    ForEach(contacts.filter { !$0.isArchived }) { contact in
                        Text(contact.displayName).tag(Optional(contact.id))
                    }
                }
                Button("新建联系人") { showContact = true }
                Button("整理找房条件") { showPaste = true }
            }
            Section("需求") {
                Picker("类型", selection: field(\.kind)) { ForEach(NeedKind.allCases) { Text($0.title).tag($0) } }
                Picker("状态", selection: field(\.status)) { ForEach(NeedStatus.allCases) { Text($0.title).tag($0) } }
                Picker("紧急程度", selection: field(\.urgency)) { ForEach(Urgency.allCases) { Text($0.title).tag($0) } }
                TextField(draft.kind == .rent ? "预算下限（元）" : "预算下限（万元）", text: field(\.budgetMin))
                TextField(draft.kind == .rent ? "预算上限（元）" : "预算上限（万元）", text: field(\.budgetMax))
                TextField("区域，顿号分隔", text: field(\.districts))
                TextField("室从", text: field(\.roomsMin)).keyboardType(.numberPad)
                TextField("室到", text: field(\.roomsMax)).keyboardType(.numberPad)
                TextField("面积从", text: field(\.areaMin)).keyboardType(.decimalPad)
                TextField("面积到", text: field(\.areaMax)).keyboardType(.decimalPad)
                Toggle("填写入住日期", isOn: field(\.hasMoveIn))
                if draft.hasMoveIn { DatePicker("入住", selection: field(\.moveIn), displayedComponents: .date) }
                TextField("必须，如电梯、车位", text: field(\.mustHave))
                TextField("排除", text: field(\.excluded))
                TextField("其他偏好", text: field(\.note), axis: .vertical)
                TextField("来源", text: field(\.source))
                if draft.status == .closed { TextField("关闭原因", text: field(\.closedReason)) }
            }
            Section("偏好小区") {
                ForEach(communities.filter { !$0.isArchived }) { community in
                    Toggle(community.name, isOn: Binding(
                        get: { draft.communityIDs.contains(community.id) },
                        set: { isOn in
                            isDirty = true
                            if isOn { draft.communityIDs.insert(community.id) } else { draft.communityIDs.remove(community.id) }
                        }
                    ))
                }
            }
        }
        .navigationTitle(existingID == nil ? "新增需求" : "编辑需求")
        .navigationBarTitleDisplayMode(.inline)
        .formExitProtection(isDirty: isDirty)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } } }
        .onAppear(perform: load)
        .sheet(isPresented: $showPaste) { pasteSheet }
        .sheet(item: $recognized) { item in
            NavigationStack { NeedTextReview(recognized: item) { apply($0); recognized = nil } }
        }
        .sheet(isPresented: $showContact) {
            NavigationStack { ContactFormView { draft.contactID = $0; isDirty = true } }
        }
        .errorAlert($errorMessage)
    }

    private var pasteSheet: some View {
        NavigationStack {
            TextEditor(text: $pasteText).padding()
                .navigationTitle("粘贴找房文字")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("关闭") { showPaste = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("识别") {
                            recognized = ClientNeedTextRecognition.recognize(pasteText, communities: communities)
                            showPaste = false
                        }
                    }
                }
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let existing = needs.first(where: { $0.id == existingID }) {
            draft = NeedDraft(existing)
        } else {
            draft.contactID = contactID
        }
    }

    private func apply(_ result: RecognizedNeed) {
        isDirty = true
        if let kind = result.kind, !result.kindNeedsConfirm { draft.kind = kind }
        if !result.budgetNeedsConfirm {
            if let min = result.budgetMinCents { draft.budgetMin = input(min) }
            if let max = result.budgetMaxCents { draft.budgetMax = input(max) }
        }
        if let min = result.bedroomsMin { draft.roomsMin = String(min) }
        if let max = result.bedroomsMax { draft.roomsMax = String(max) }
        if let min = result.areaMin { draft.areaMin = String(min) }
        if let max = result.areaMax { draft.areaMax = String(max) }
        if !result.districts.isEmpty { draft.districts = result.districts.joined(separator: "、") }
        if !result.communityNeedsConfirm { draft.communityIDs.formUnion(result.communityIDs) }
        if !result.featureNeedsConfirm {
            draft.mustHave = result.mustHave.joined(separator: "、")
            draft.excluded = result.excluded.joined(separator: "、")
        }
    }

    private func input(_ cents: Int) -> String {
        if draft.kind == .rent { return String(Money.yuan(fromCents: cents)) }
        return String(Money.wan(fromCents: cents))
    }

    private func save() {
        guard draft.contactID != nil else { errorMessage = "先选择联系人。"; return }
        if draft.status == .closed && BusinessRules.trimmed(draft.closedReason).isEmpty {
            errorMessage = "关闭需求必须填写原因。"
            return
        }
        let need = needs.first { $0.id == existingID } ?? ClientNeed()
        if existingID == nil { context.insert(need) }
        need.contact = contacts.first { $0.id == draft.contactID }
        if let contact = need.contact {
            if need.kind == .rent, !contact.roles.contains(.tenant) { contact.roles.append(.tenant) }
            if need.kind != .rent, !contact.roles.contains(.buyer) { contact.roles.append(.buyer) }
        }
        need.kind = draft.kind
        need.status = draft.status
        need.urgency = draft.urgency
        let parse: (String) -> Int = { text in
            guard let value = Double(text) else { return 0 }
            return draft.kind == .rent ? Money.cents(fromYuan: value) : Money.cents(fromWan: value)
        }
        need.budgetMinCents = parse(draft.budgetMin)
        need.budgetMaxCents = parse(draft.budgetMax)
        need.preferredDistricts = BusinessRules.splitList(draft.districts)
        need.preferredCommunityIDs = Array(draft.communityIDs)
        need.bedroomsMin = Int(draft.roomsMin) ?? 0
        need.bedroomsMax = Int(draft.roomsMax) ?? 0
        need.areaMin = Double(draft.areaMin) ?? 0
        need.areaMax = Double(draft.areaMax) ?? 0
        need.moveInDate = draft.hasMoveIn ? draft.moveIn : nil
        need.mustHaveFeatures = BusinessRules.splitList(draft.mustHave)
        need.excludedFeatures = BusinessRules.splitList(draft.excluded)
        need.preferencesNote = BusinessRules.trimmed(draft.note)
        need.source = BusinessRules.trimmed(draft.source)
        need.closedReason = BusinessRules.trimmed(draft.closedReason)
        need.updatedAt = Date()
        try? context.save()
        isDirty = false
        dismiss()
    }

    private func field<T: Equatable>(_ keyPath: WritableKeyPath<NeedDraft, T>) -> Binding<T> {
        Binding(get: { draft[keyPath: keyPath] }, set: { newValue in
            if draft[keyPath: keyPath] != newValue { isDirty = true }
            draft[keyPath: keyPath] = newValue
        })
    }
}

struct NeedDraft: Equatable {
    var contactID: UUID?
    var kind: NeedKind = .buy
    var status: NeedStatus = .active
    var urgency: Urgency = .normal
    var budgetMin = ""
    var budgetMax = ""
    var districts = ""
    var roomsMin = ""
    var roomsMax = ""
    var areaMin = ""
    var areaMax = ""
    var hasMoveIn = false
    var moveIn = Date()
    var mustHave = ""
    var excluded = ""
    var note = ""
    var source = ""
    var closedReason = ""
    var communityIDs: Set<UUID> = []

    init() {}

    init(_ need: ClientNeed) {
        contactID = need.contact?.id
        kind = need.kind
        status = need.status
        urgency = need.urgency
        if need.budgetMinCents > 0 {
            budgetMin = kind == .rent ? String(Money.yuan(fromCents: need.budgetMinCents)) : String(Money.wan(fromCents: need.budgetMinCents))
        }
        if need.budgetMaxCents > 0 {
            budgetMax = kind == .rent ? String(Money.yuan(fromCents: need.budgetMaxCents)) : String(Money.wan(fromCents: need.budgetMaxCents))
        }
        districts = need.preferredDistricts.joined(separator: "、")
        if need.bedroomsMin > 0 { roomsMin = String(need.bedroomsMin) }
        if need.bedroomsMax > 0 { roomsMax = String(need.bedroomsMax) }
        if need.areaMin > 0 { areaMin = String(need.areaMin) }
        if need.areaMax > 0 { areaMax = String(need.areaMax) }
        if let date = need.moveInDate { hasMoveIn = true; moveIn = date }
        mustHave = need.mustHaveFeatures.joined(separator: "、")
        excluded = need.excludedFeatures.joined(separator: "、")
        note = need.preferencesNote
        source = need.source
        closedReason = need.closedReason
        communityIDs = Set(need.preferredCommunityIDs)
    }
}

struct NeedTextReview: View {
    var recognized: RecognizedNeed
    var onUse: (RecognizedNeed) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Text("冲突或含糊的内容不会自动填写。")
                    .font(.footnote).foregroundStyle(Theme.muted)
                ForEach(recognized.warnings, id: \.self) { Text($0).foregroundStyle(Theme.warn) }
            }
            Section("将写入") {
                LabeledContent("类型", value: recognized.kindNeedsConfirm ? "需手动确认" : (recognized.kind?.title ?? "未识别"))
                LabeledContent("预算", value: recognized.budgetNeedsConfirm ? "需手动确认" : budget)
                LabeledContent("户型", value: rooms)
                LabeledContent("区域", value: recognized.districts.joined(separator: "、"))
                LabeledContent("必须", value: recognized.featureNeedsConfirm ? "需手动确认" : recognized.mustHave.joined(separator: "、"))
                LabeledContent("排除", value: recognized.excluded.joined(separator: "、"))
            }
        }
        .navigationTitle("核对找房条件")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("填入") { onUse(recognized); dismiss() } }
        }
    }

    private var budget: String {
        if recognized.budgetMinCents == nil && recognized.budgetMaxCents == nil { return "未识别" }
        return "\(recognized.budgetMinCents ?? 0) – \(recognized.budgetMaxCents ?? 0) 分"
    }

    private var rooms: String {
        guard let min = recognized.bedroomsMin else { return "未识别" }
        return "\(min)–\(recognized.bedroomsMax ?? min)室"
    }
}

struct MatchPropertiesView: View {
    var needID: UUID
    @Query private var needs: [ClientNeed]
    @Query private var properties: [Property]
    @Query private var viewings: [Viewing]
    private var rows: [MatchRow] {
        guard let need = needs.first(where: { $0.id == needID }) else { return [] }
        return MatchingService.properties(for: need, properties: properties, viewings: viewings)
    }

    var body: some View {
        List {
            ForEach(MatchBucket.allCases) { bucket in
                let items = rows.filter { $0.bucket == bucket }
                if !items.isEmpty {
                    Section(bucket.title) {
                        ForEach(items) { row in
                            if let id = row.propertyID {
                                NavigationLink(value: RecordRoute.property(id)) { matchLabel(row) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("匹配房源")
    }
}

struct MatchNeedsView: View {
    var propertyID: UUID
    @Query private var properties: [Property]
    @Query private var needs: [ClientNeed]
    @Query private var viewings: [Viewing]
    private var rows: [MatchRow] {
        guard let property = properties.first(where: { $0.id == propertyID }) else { return [] }
        return MatchingService.needs(for: property, needs: needs.filter { $0.status != .closed }, viewings: viewings)
    }

    var body: some View {
        List {
            ForEach(MatchBucket.allCases) { bucket in
                let items = rows.filter { $0.bucket == bucket }
                if !items.isEmpty {
                    Section(bucket.title) {
                        ForEach(items) { row in
                            if let id = row.needID {
                                NavigationLink(value: RecordRoute.need(id)) { matchLabel(row) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("匹配客户")
    }
}

private func matchLabel(_ row: MatchRow) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(row.title)
        Text(row.subtitle).font(.subheadline).foregroundStyle(Theme.muted)
        ForEach(row.notes, id: \.self) { note in
            Text(note).font(.caption).foregroundStyle(Theme.muted)
        }
    }
}
